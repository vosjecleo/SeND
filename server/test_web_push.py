import base64
import json
import os
import pathlib
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import web_push as gateway


def subscription(endpoint='https://web.push.apple.com/test'):
    def encode(value):
        return base64.urlsafe_b64encode(value).decode().rstrip('=')
    return {'endpoint': endpoint, 'keys': {'p256dh': encode(b'\x04' + b'a' * 64), 'auth': encode(b'b' * 16)}}


class WebPushTests(unittest.TestCase):
    def test_malformed_json_shapes_are_rejected(self):
        for route in ['visibility', 'unsubscribe', '_matrix/push/v1/notify']:
            for body in [[], 'not an object']:
                response = gateway.app.test_client().post('/api/push/' + route, json=body)
                self.assertEqual(response.status_code, 400)
        with self.assertRaises(ValueError):
            gateway.validate_subscription({'endpoint': 'https://web.push.apple.com/x', 'keys': []})

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.state = mock.patch.object(gateway, 'STATE', self.temp.name)
        self.state.start()
        self.addCleanup(self.state.stop)
        self.addCleanup(self.temp.cleanup)
        self.client = gateway.app.test_client()

    def register(self):
        with mock.patch.object(gateway, 'verified_user', return_value='@test:deltie.net'):
            response = self.client.post('/api/push/subscribe', json={'openid': {}, 'subscription': subscription()})
        self.assertEqual(response.status_code, 200)
        return response.json['pushkey']

    def test_fixed_push_origins_and_key_lengths(self):
        for url in ['http://web.push.apple.com/test', 'https://127.0.0.1/test',
                    'https://web.push.apple.com.evil/test', 'https://user@web.push.apple.com/test',
                    'https://web.push.apple.com:444/test', 'https://web.push.apple.com/test#x']:
            with self.subTest(url=url), self.assertRaises(ValueError):
                gateway.validate_subscription(subscription(url))
        with self.assertRaises(ValueError):
            gateway.validate_subscription({'endpoint': 'https://web.push.apple.com/x', 'keys': {'auth': 'a'}})
        self.assertEqual(gateway.validate_subscription(subscription()), subscription())

    def test_openid_issuer_cannot_trigger_arbitrary_url_fetch(self):
        with mock.patch('urllib.request.build_opener') as opener:
            with self.assertRaises(ValueError):
                gateway.verified_user({'matrix_server_name': '127.0.0.1', 'access_token': 'test'})
            opener.assert_not_called()

    def test_registration_is_idempotent_private_and_does_not_store_openid(self):
        key = self.register()
        self.assertEqual(key, self.register())
        self.assertGreaterEqual(len(key), 40)
        self.assertEqual(os.stat(self.temp.name).st_mode & 0o777, 0o700)
        self.assertEqual(os.stat(self.temp.name + '/subscriptions.sqlite').st_mode & 0o777, 0o600)
        with gateway.database() as db:
            row = db.execute('SELECT subscription FROM subscriptions').fetchone()[0]
            self.assertNotIn('openid', row)
            self.assertNotIn('access_token', row)

    def test_foreground_suppression_and_background_delivery_ids_only(self):
        key = self.register()
        payload = {'notification': {'room_id': '!room:example', 'event_id': '$event',
                   'content': {'body': 'must never forward this'},
                   'devices': [{'app_id': 'net.deltie.deltiecord.web', 'pushkey': key}]}}
        with mock.patch.object(gateway, 'send') as send:
            response = self.client.post('/api/push/_matrix/push/v1/notify', json=payload)
            self.assertEqual(response.status_code, 200)
            gateway.drain_pending()
            send.assert_not_called()
            self.client.post('/api/push/visibility', json={'pushkey': key, 'visible': False})
            gateway.drain_pending()
            self.assertEqual(send.call_args.args[1], {'room_id': '!room:example', 'event_id': '$event'})
        self.client.post('/api/push/unsubscribe', json={'pushkey': key})
        response = self.client.post('/api/push/_matrix/push/v1/notify', json=payload)
        self.assertEqual(response.json, {'rejected': [key]})

    def test_unknown_capability_never_sends(self):
        with mock.patch.object(gateway, 'send') as send:
            response = self.client.post('/api/push/_matrix/push/v1/notify', json={
                'notification': {'room_id': '!room:example', 'event_id': '$event',
                  'devices': [{'app_id': 'net.deltie.deltiecord.web', 'pushkey': 'wrong'}]}})
            self.assertEqual(response.json, {'rejected': ['wrong']})
            send.assert_not_called()

    def test_expired_foreground_lease_delivers_retained_notification(self):
        key = self.register()
        with gateway.database() as db:
            db.execute('UPDATE subscriptions SET visible_until=0 WHERE id=?', (key,))
        with mock.patch.object(gateway, 'send') as send:
            response = self.client.post('/api/push/_matrix/push/v1/notify', json={
                'notification': {'room_id': '!room:test', 'event_id': '$event',
                    'devices': [{'app_id': 'net.deltie.deltiecord.web', 'pushkey': key}]}})
            self.assertEqual(response.status_code, 200)
            gateway.drain_pending()
            send.assert_called_once()

    def queue(self, key, event='$event'):
        return self.client.post('/_matrix/push/v1/notify', json={
            'notification': {'room_id': '!room:test', 'event_id': event,
                'devices': [{'app_id': 'net.deltie.deltiecord.web', 'pushkey': key}]}})

    def test_standard_matrix_path_accepts_and_persists_events(self):
        key = self.register()
        self.assertEqual(self.queue(key).status_code, 200)
        with gateway.database() as db:
            self.assertEqual(db.execute('SELECT event FROM pending').fetchall(), [('$event',)])
        # A later drain, using only persisted state, delivers after lease expiry.
        with gateway.database() as db:
            db.execute('UPDATE subscriptions SET visible_until=0')
        with mock.patch.object(gateway, 'send') as send:
            gateway.drain_pending()
            send.assert_called_once()

    def test_pending_events_coalesce_and_read_cancels_only_owned_room(self):
        key = self.register()
        self.queue(key, '$one'); self.queue(key, '$two')
        with gateway.database() as db:
            self.assertEqual(db.execute('SELECT event FROM pending').fetchall(), [('$two',)])
        self.client.post('/api/push/read', json={'pushkey': 'wrong', 'room_id': '!room:test'})
        with gateway.database() as db:
            self.assertEqual(db.execute('SELECT COUNT(*) FROM pending').fetchone()[0], 1)
        self.client.post('/api/push/read', json={'pushkey': key, 'room_id': '!room:test'})
        self.client.post('/api/push/visibility', json={'pushkey': key, 'visible': False})
        with mock.patch.object(gateway, 'send') as send:
            gateway.drain_pending(); send.assert_not_called()

    def test_transient_delivery_errors_retain_queue_and_retry(self):
        key = self.register(); self.queue(key)
        self.client.post('/api/push/visibility', json={'pushkey': key, 'visible': False})
        with mock.patch.object(gateway, 'send', side_effect=RuntimeError('temporary')):
            gateway.drain_pending()
        with gateway.database() as db:
            self.assertEqual(db.execute('SELECT attempts FROM pending').fetchone()[0], 1)
            db.execute('UPDATE pending SET retry_at=0')
        with mock.patch.object(gateway, 'send') as send:
            gateway.drain_pending(); send.assert_called_once()
        with gateway.database() as db:
            self.assertEqual(db.execute('SELECT COUNT(*) FROM pending').fetchone()[0], 0)

    def test_expired_pending_and_unsubscribed_devices_never_deliver(self):
        key = self.register(); self.queue(key)
        with gateway.database() as db:
            db.execute('UPDATE pending SET expires=0')
        with mock.patch.object(gateway, 'send') as send:
            gateway.drain_pending(); send.assert_not_called()
        self.queue(key)
        self.client.post('/api/push/unsubscribe', json={'pushkey': key})
        with gateway.database() as db:
            self.assertEqual(db.execute('SELECT COUNT(*) FROM pending').fetchone()[0], 0)

    def test_zero_unread_badge_cancels_retained_alerts(self):
        key = self.register(); self.queue(key)
        response = self.client.post('/_matrix/push/v1/notify', json={'notification': {
            'counts': {'unread': 0}, 'devices': [{'app_id': 'net.deltie.deltiecord.web', 'pushkey': key}]}})
        self.assertEqual(response.status_code, 200)
        with gateway.database() as db:
            self.assertEqual(db.execute('SELECT COUNT(*) FROM pending').fetchone()[0], 0)

    def test_queue_bounds_do_not_ack_unstored_notifications(self):
        key = self.register()
        with gateway.database() as db:
            db.executemany('INSERT INTO pending VALUES (?,?,?,?,0,0)',
                           [(key, f'!room{i}', '$event', gateway.time.time()+3600) for i in range(256)])
        self.assertEqual(self.queue(key).status_code, 503)

    def test_expired_provider_subscription_is_removed(self):
        key = self.register(); self.queue(key)
        self.client.post('/api/push/visibility', json={'pushkey': key, 'visible': False})
        error = gateway.WebPushException('gone', response=mock.Mock(status_code=410))
        with mock.patch.object(gateway, 'send', side_effect=error):
            gateway.drain_pending()
        with gateway.database() as db:
            self.assertEqual(db.execute('SELECT COUNT(*) FROM subscriptions').fetchone()[0], 0)
            self.assertEqual(db.execute('SELECT COUNT(*) FROM pending').fetchone()[0], 0)

    def test_user_initiated_push_requires_capability_but_bypasses_visibility(self):
        with mock.patch.object(gateway, 'send') as send:
            self.assertEqual(self.client.post('/api/push/test', json={'pushkey': 'wrong'}).status_code, 404)
            send.assert_not_called()
            key = self.register()
            self.assertEqual(self.client.post('/api/push/test', json={'pushkey': key}).status_code, 200)
            self.assertTrue(send.call_args.args[1]['test'])


if __name__ == '__main__':
    unittest.main()
