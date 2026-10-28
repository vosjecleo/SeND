#!/usr/bin/env python3
"""Read-only per-user Synapse media inventory. Never deletes or downloads media.

Use a server-local admin token file. Output contains aggregate sizes, not names,
MXC URLs, access tokens or message contents. The quota is a proposed allowance,
not an upload limit enforced by this audit tool.
"""
import argparse
from collections import Counter
import json
import os
from pathlib import Path
import stat
from urllib.parse import quote, urlencode, urlsplit
from urllib.request import Request, build_opener, HTTPRedirectHandler

DEFAULT_QUOTA_BYTES = 12 * 1024**3


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def validate_origin(value):
    url = urlsplit(value)
    if (url.username or url.password or url.query or url.fragment
            or url.path not in ('', '/') or not url.hostname
            or (url.scheme != 'https' and not (
                url.scheme == 'http' and url.hostname in ('127.0.0.1', '::1', 'localhost')))):
        raise ValueError('Use an HTTPS origin, or a local loopback HTTP origin.')
    return value.rstrip('/')


def read_token(path):
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(descriptor) as stream:
        info = os.fstat(stream.fileno())
        if (not stat.S_ISREG(info.st_mode) or info.st_mode & 0o077
                or info.st_uid != os.geteuid()):
            raise ValueError('The token must be an owner-only file owned by this user.')
        token = stream.read(16385).strip()
    if not token or len(token) > 16384 or any(c.isspace() for c in token):
        raise ValueError('Invalid admin token file.')
    return token


def media_kind(mime):
    mime = (mime or '').split(';')[0].strip().lower()
    if mime == 'image/gif':
        return 'gifs'
    if mime.startswith('image/'):
        return 'images'
    if mime.startswith('video/'):
        return 'videos'
    if mime.startswith('audio/'):
        return 'audio'
    return 'other'


def inventory(fetch_page, quota_bytes=DEFAULT_QUOTA_BYTES):
    """Synapse owner-media accounting, not database/thumbnails/replica size."""
    sizes, counts = Counter(), Counter()
    cursor, cursors, seen = 0, set(), set()
    for _ in range(10000):
        if cursor in cursors:
            raise ValueError('Synapse repeated an inventory cursor.')
        cursors.add(cursor)
        page = fetch_page(cursor)
        if not isinstance(page.get('media'), list):
            raise ValueError('Invalid Synapse media response.')
        for item in page['media']:
            media_id = item.get('media_id')
            length = item.get('media_length')
            if not isinstance(media_id, str) or not media_id:
                raise ValueError('Invalid media identifier.')
            if media_id in seen:
                raise ValueError('Inventory changed during pagination. Retry the audit.')
            seen.add(media_id)
            if length is None:  # Reserved MXC URI, no uploaded bytes yet.
                continue
            if not isinstance(length, int) or isinstance(length, bool) or length < 0:
                raise ValueError('Invalid media length.')
            kind = media_kind(item.get('media_type'))
            sizes[kind] += length
            counts[kind] += 1
        next_cursor = page.get('next_token')
        if next_cursor is None:
            break
        if not isinstance(next_cursor, int) or isinstance(next_cursor, bool) or next_cursor <= cursor:
            raise ValueError('Invalid Synapse inventory cursor.')
        cursor = next_cursor
    else:
        raise ValueError('Inventory exceeded the audit page limit.')
    used = sum(sizes.values())
    return {
        'version': 1,
        'accounting': 'synapse_owner_media_bytes',
        'quota_bytes': quota_bytes,
        'quota_enforced_by_this_tool': False,
        'used_bytes': used,
        'remaining_bytes': max(0, quota_bytes - used),
        'over_quota_bytes': max(0, used - quota_bytes),
        'categories': {kind: {'bytes': sizes[kind], 'files': counts[kind]}
                       for kind in ('images', 'videos', 'gifs', 'audio', 'other')},
        'message_storage_bytes': None,
        'encrypted_upload_types_known': False,
        'klipy_source_known': False,
        'notes': [
            'Encrypted uploads cannot be classified without client-supplied labels.',
            'GIF MIME type does not identify Klipy as the source.',
            'Messages, generated thumbnails, remote caches and backups are not counted.',
            'Synapse may include URL-preview images attributed to this user.',
            'The configured quota is an allowance for reporting, not enforcement.',
        ],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--synapse', required=True, help='HTTPS or local loopback origin')
    parser.add_argument('--admin-token-file', required=True, type=Path)
    parser.add_argument('--user', required=True, help='Local Matrix user ID')
    args = parser.parse_args()
    try:
        origin, token = validate_origin(args.synapse), read_token(args.admin_token_file)
        if not args.user.startswith('@') or ':' not in args.user or len(args.user) > 255:
            raise ValueError('Enter a complete Matrix user ID.')
        opener = build_opener(NoRedirect())

        def fetch(cursor):
            url = origin + '/_synapse/admin/v1/users/' + quote(args.user, safe='') + '/media?'
            url += urlencode({'from': cursor, 'limit': 100, 'order_by': 'media_id', 'dir': 'f'})
            req = Request(url, headers={'Authorization': 'Bearer ' + token})
            with opener.open(req, timeout=30) as response:
                body = response.read(2 * 1024 * 1024 + 1)
            if len(body) > 2 * 1024 * 1024:
                raise ValueError('Synapse inventory page is too large.')
            return json.loads(body)

        print(json.dumps(inventory(fetch), indent=2))
    except ValueError as error:
        parser.exit(1, str(error) + '\n')
    except Exception:
        # HTTP exception strings can expose sensitive response details.
        parser.exit(1, 'Inventory failed. Check the local endpoint, admin token and Synapse version.\n')


if __name__ == '__main__':
    main()
