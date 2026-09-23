#!/usr/bin/env python3
"""Deltiecord Web Push gateway. Run behind HTTPS with ONE bounded WSGI worker.

Matrix supplies event IDs only. Short-lived OpenID proofs authenticate signups;
Matrix access tokens, room keys, and message plaintext never enter this service.
Subscription endpoints and pushkeys are capabilities: do not log request bodies.
"""
import base64
from contextlib import contextmanager
import hashlib
import ipaddress
import json
import os
import secrets
import socket
import sqlite3
import threading
import time
from urllib.parse import urlencode, urlsplit
import urllib.request

from flask import Flask, jsonify, request
from pywebpush import WebPushException, webpush
from cryptography.hazmat.primitives import serialization

from giphy_proxy import _allowed, _client_identity

app = Flask(__name__)
app.config['MAX_CONTENT_LENGTH'] = 64 * 1024
STATE = os.environ.get('WEB_PUSH_STATE', '/var/lib/deltiecord-web-push')
KEY = os.environ.get('WEB_PUSH_PRIVATE_KEY', STATE + '/vapid.pem')
CONTACT = os.environ.get('WEB_PUSH_CONTACT', 'mailto:admin@deltie.net')
# No dynamic discovery/redirects: an OpenID issuer must be deliberately enabled.
ISSUERS = {'deltie.net': 'https://matrix.deltie.net',
           'matrix.deltie.net': 'https://matrix.deltie.net'}
PUSH_HOSTS = {'web.push.apple.com', 'fcm.googleapis.com',
              'updates.push.services.mozilla.com'}
_lock = threading.Lock()


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


@contextmanager
def database():
    os.makedirs(STATE, mode=0o700, exist_ok=True)
    os.chmod(STATE, 0o700)
    db = sqlite3.connect(STATE + '/subscriptions.sqlite', timeout=10)
    os.chmod(STATE + '/subscriptions.sqlite', 0o600)
    db.execute('CREATE TABLE IF NOT EXISTS subscriptions '
               '(id TEXT PRIMARY KEY, owner TEXT NOT NULL, endpoint_hash TEXT UNIQUE NOT NULL, '
               'subscription TEXT NOT NULL, seen REAL NOT NULL, visible_until REAL NOT NULL DEFAULT 0)')
    try:
        with db:
            yield db
    finally:
        db.close()


def validate_subscription(value):
    if not isinstance(value, dict):
        raise ValueError('Invalid subscription')
    endpoint = value.get('endpoint')
    if not isinstance(endpoint, str) or len(endpoint) > 4096:
        raise ValueError('Invalid endpoint')
    url = urlsplit(endpoint)
    if (url.scheme != 'https' or url.hostname not in PUSH_HOSTS or url.username
            or url.password or url.port not in (None, 443) or url.fragment):
        raise ValueError('Unsupported push service')
    keys = value.get('keys', {})
    if not isinstance(keys, dict):
        raise ValueError('Invalid subscription keys')
    normalized = {}
    for name, length in [('p256dh', 65), ('auth', 16)]:
        text = keys.get(name)
        if not isinstance(text, str) or len(text) > 128:
            raise ValueError('Invalid subscription key')
        raw = base64.b64decode(text + '=' * (-len(text) % 4), altchars=b'-_', validate=True)
        if len(raw) != length or (name == 'p256dh' and raw[0] != 4):
            raise ValueError('Invalid subscription key')
        normalized[name] = text
    return {'endpoint': endpoint, 'keys': normalized}


def verified_user(proof):
    if not isinstance(proof, dict):
        raise ValueError('Missing OpenID proof')
    issuer = ISSUERS.get(proof.get('matrix_server_name'))
    token = proof.get('access_token')
    if issuer is None or not isinstance(token, str) or not 1 <= len(token) <= 4096:
        raise ValueError('Unsupported OpenID issuer')
    url = issuer + '/_matrix/federation/v1/openid/userinfo?' + urlencode({'access_token': token})
    with urllib.request.build_opener(NoRedirect).open(url, timeout=8) as response:
        body = response.read(8193)
        if len(body) > 8192:
            raise ValueError('Invalid OpenID response')
        user = json.loads(body).get('sub')
    if not isinstance(user, str) or not user.startswith('@') or len(user) > 1024:
        raise ValueError('Invalid OpenID user')
    return user


def public_key():
    if os.stat(KEY).st_mode & 0o077:
        raise RuntimeError('VAPID key must be owner-only')
    with open(KEY, 'rb') as source:
        key = serialization.load_pem_private_key(source.read(), password=None)
    raw = key.public_key().public_bytes(serialization.Encoding.X962,
                                        serialization.PublicFormat.UncompressedPoint)
    return base64.urlsafe_b64encode(raw).decode().rstrip('=')


@app.before_request
def limit_requests():
    peer = _client_identity(request.remote_addr, request.headers.get('X-Real-IP'))
    namespace = 'webpush-notify' if request.path.endswith('/notify') else 'webpush-client'
    if not _allowed(peer, 240, namespace):
        return jsonify(error='Try again later'), 429


@app.after_request
def private_response(response):
    response.headers['Cache-Control'] = 'no-store'
    return response


@app.get('/api/push/config')
def config():
    return jsonify(public_key=public_key())


@app.post('/api/push/subscribe')
def subscribe():
    try:
        body = request.get_json()
        subscription = validate_subscription(body.get('subscription'))
        owner = verified_user(body.get('openid'))
        digest = hashlib.sha256(subscription['endpoint'].encode()).hexdigest()
        with _lock, database() as db:
            db.execute('DELETE FROM subscriptions WHERE seen < ?', (time.time() - 90 * 86400,))
            existing = db.execute('SELECT id, owner FROM subscriptions WHERE endpoint_hash=?', (digest,)).fetchone()
            if existing and existing[1] != owner:
                return jsonify(error='Subscription belongs to another account'), 409
            if not existing and (db.execute('SELECT COUNT(*) FROM subscriptions WHERE owner=?', (owner,)).fetchone()[0] >= 10
                                 or db.execute('SELECT COUNT(*) FROM subscriptions').fetchone()[0] >= 10000):
                return jsonify(error='Subscription limit reached'), 429
            key = existing[0] if existing else secrets.token_urlsafe(32)
            db.execute('INSERT OR REPLACE INTO subscriptions VALUES (?,?,?,?,?,?)',
                       (key, owner, digest, json.dumps(subscription), time.time(), time.time() + 60))
        return jsonify(pushkey=key)
    except Exception:
        # Never log exceptions containing the OpenID token or push endpoint.
        return jsonify(error='Could not verify browser subscription'), 400


@app.post('/api/push/visibility')
def visibility():
    body = request.get_json()
    if not isinstance(body, dict):
        return jsonify(error='Invalid request'), 400
    key = body.get('pushkey')
    if not isinstance(key, str) or len(key) > 256:
        return jsonify(error='Invalid capability'), 400
    with _lock, database() as db:
        db.execute('UPDATE subscriptions SET visible_until=?, seen=? WHERE id=?',
                   (time.time() + 60 if body.get('visible') is True else 0, time.time(), key))
    return jsonify(ok=True)


@app.post('/api/push/unsubscribe')
def unsubscribe():
    body = request.get_json()
    if not isinstance(body, dict):
        return jsonify(error='Invalid request'), 400
    key = body.get('pushkey')
    if not isinstance(key, str) or len(key) > 256:
        return jsonify(error='Invalid capability'), 400
    with _lock, database() as db:
        db.execute('DELETE FROM subscriptions WHERE id=?', (key,))
    return jsonify(ok=True)


def send(subscription, payload):
    # Exact provider hosts only. Reject private resolutions as defence in depth;
    # HTTPS still authenticates the fixed provider hostname. Never follow redirects.
    host = urlsplit(subscription['endpoint']).hostname
    addresses = socket.getaddrinfo(host, 443, type=socket.SOCK_STREAM)
    if not addresses or any(not ipaddress.ip_address(item[4][0]).is_global for item in addresses):
        raise ValueError('Unsafe push resolution')
    import requests
    class NoRedirectSession(requests.Session):
        def request(self, *args, **kwargs):
            kwargs['allow_redirects'] = False
            return super().request(*args, **kwargs)
    with NoRedirectSession() as session:
        return webpush(subscription_info=subscription, data=json.dumps(payload),
                       vapid_private_key=KEY, vapid_claims={'sub': CONTACT},
                       ttl=300, timeout=8, requests_session=session)


@app.post('/api/push/_matrix/push/v1/notify')
def notify():
    body = request.get_json()
    if not isinstance(body, dict) or not isinstance(body.get('notification'), dict):
        return jsonify(error='Invalid notification'), 400
    notification = body['notification']
    room = notification.get('room_id', '')
    event = notification.get('event_id', '')
    devices = notification.get('devices', [])
    if (not isinstance(room, str) or len(room) > 1024 or not isinstance(event, str)
            or len(event) > 1024 or not isinstance(devices, list) or len(devices) > 20):
        return jsonify(error='Invalid notification'), 400
    rejected = []
    for device in devices:
        if not isinstance(device, dict) or device.get('app_id') != 'net.deltie.deltiecord.web':
            continue
        key = device.get('pushkey')
        if not isinstance(key, str) or len(key) > 256:
            continue
        with _lock, database() as db:
            row = db.execute('SELECT subscription,visible_until FROM subscriptions WHERE id=?', (key,)).fetchone()
        if not row:
            rejected.append(key)
            continue
        if row[1] > time.time() or not room or not event:
            continue
        try:
            send(validate_subscription(json.loads(row[0])), {'room_id': room, 'event_id': event})
        except WebPushException as error:
            if error.response is not None and error.response.status_code in (404, 410):
                with _lock, database() as db:
                    db.execute('DELETE FROM subscriptions WHERE id=?', (key,))
                rejected.append(key)
            else:
                return jsonify(error='Push delivery temporarily unavailable'), 503
        except Exception:
            return jsonify(error='Push delivery temporarily unavailable'), 503
    return jsonify(rejected=rejected)
