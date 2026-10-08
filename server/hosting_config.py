"""Operator-controlled public endpoints, never inferred from request headers."""
import json
import os
from urllib.parse import urlsplit


def https_origin(value):
    url = urlsplit(value)
    if (url.scheme != 'https' or not url.hostname or url.username or url.password
            or url.path not in ('', '/') or url.query or url.fragment
            or url.port not in (None, 443)):
        raise ValueError('Expected an HTTPS origin without a path')
    return value.rstrip('/')


APP_ORIGIN = https_origin(os.environ.get('SEND_APP_ORIGIN', 'https://chat.deltie.net'))


def openid_issuers():
    raw = os.environ.get('WEB_PUSH_ISSUERS')
    if raw is None:
        return {'deltie.net': 'https://matrix.deltie.net',
                'matrix.deltie.net': 'https://matrix.deltie.net'}
    values = json.loads(raw)
    if not isinstance(values, dict) or not values:
        raise ValueError('WEB_PUSH_ISSUERS must be a nonempty JSON object')
    return {name: https_origin(origin) for name, origin in values.items()}
