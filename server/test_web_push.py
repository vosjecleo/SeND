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
            send.assert_not_called()
            self.client.post('/api/push/visibility', json={'pushkey': key, 'visible': False})
            response = self.client.post('/api/push/_matrix/push/v1/notify', json=payload)
            self.assertEqual(response.status_code, 200)
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


if __name__ == '__main__':
    unittest.main()
