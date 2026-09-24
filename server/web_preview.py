"""Bounded anonymous preview bridge for the PWA's existing trusted providers.

No cookies, credentials, arbitrary headers, conversion, or private destinations.
Connections are pinned to validated DNS answers; TLS still verifies the hostname.
"""
import http.client
import ipaddress
import re
import socket
import ssl
import threading
import time
from urllib.parse import parse_qs, urlsplit, urljoin

PROVIDERS = frozenset(('youtube.com', 'youtu.be', 'youtube-nocookie.com',
    'ytimg.com', 'googlevideo.com', 'vimeo.com', 'vimeocdn.com', 'twitch.tv',
    'ttvnw.net', 'streamable.com', 'giphy.com', 'klipy.com', 'tenor.com',
    'tenor.googleapis.com', 'imgur.com', 'reddit.com', 'redd.it',
    'redditmedia.com', 'redditstatic.com', 'bsky.app', 'bsky.social',
    'tiktok.com', 'tiktokcdn.com', 'x.com', 'twitter.com', 'twimg.com',
    'fxtwitter.com'))
SLOTS = threading.BoundedSemaphore(4)
LIMITS = {'document': 1024 * 1024, 'image': 5 * 1024 * 1024,
          'video': 8 * 1024 * 1024}


def validate_url(url):
    parsed = urlsplit(url)
    host = (parsed.hostname or '').lower()
    if (len(url) > 4096 or parsed.scheme != 'https' or parsed.username is not None
            or parsed.password is not None or parsed.port not in (None, 443)
            or not any(host == domain or host.endswith('.' + domain) for domain in PROVIDERS)):
        raise ValueError('Unsupported preview provider')
    return parsed


def public_addresses(host):
    answers = socket.getaddrinfo(host, 443, type=socket.SOCK_STREAM)
    if not answers:
        raise ValueError('Missing address')
    for _, _, _, _, address in answers:
        ip = ipaddress.ip_address(address[0])
        if (not ip.is_global or ip.is_multicast or
                (isinstance(ip, ipaddress.IPv6Address) and
                 (ip.ipv4_mapped or ip.sixtofour or ip.teredo or
                  ip in ipaddress.ip_network('64:ff9b::/96') or
                  ip in ipaddress.ip_network('64:ff9b:1::/48')))):
            raise ValueError('Non-public address')
    return answers


def upstream(url, kind, byte_range):
    for _ in range(5):
        parsed = validate_url(url)
        answers = public_addresses(parsed.hostname)
        family, socktype, proto, _, address = answers[0]
        raw = socket.socket(family, socktype, proto)
        raw.settimeout(12)
        connection = http.client.HTTPSConnection(parsed.hostname, timeout=12)
        try:
            raw.connect(address)
            connection.sock = ssl.create_default_context().wrap_socket(
                raw, server_hostname=parsed.hostname)
            headers = {'Accept-Encoding': 'identity', 'User-Agent': 'Deltiecord/preview',
                       'Accept': {'document': 'text/html,application/xhtml+xml',
                                  'image': 'image/*', 'video': 'video/*'}[kind]}
            if byte_range:
                headers['Range'] = byte_range
            connection.request('GET', (parsed.path or '/') +
                               ('?' + parsed.query if parsed.query else ''), headers=headers)
            response = connection.getresponse()
            if response.status in (301, 302, 303, 307, 308):
                location = response.getheader('Location')
                if not location:
                    raise ValueError('Invalid redirect')
                url = urljoin(url, location)
                connection.close()
                continue
            return connection, response
        except Exception:
            connection.close()
            raw.close()
            raise
    raise ValueError('Too many redirects')


def range_for_request(value):
    if not value:
        return 'bytes=0-8388607'
    match = re.fullmatch(r'bytes=(\d+)-(\d*)', value)
    if not match:
        raise ValueError('Invalid range')
    start = int(match[1])
    end = min(int(match[2]) if match[2] else start + LIMITS['video'] - 1,
              start + LIMITS['video'] - 1)
    if start > end or end >= 512 * 1024 * 1024:
        raise ValueError('Invalid range')
    return f'bytes={start}-{end}'


def handle(handler, allowed, client):
    if not allowed(client, 120, 'web-preview') or not SLOTS.acquire(blocking=False):
        handler._json({'error': 'Preview service busy; try again shortly'}, 429)
        return
    connection = None
    try:
        query = parse_qs(urlsplit(handler.path).query)
        url = query.get('url', [''])[0]
        kind = query.get('kind', ['document'])[0]
        if kind not in LIMITS:
            raise ValueError('Invalid media kind')
        byte_range = range_for_request(query.get('range', [handler.headers.get('Range', '')])[0]) if kind == 'video' else None
        connection, response = upstream(url, kind, byte_range)
        mime = response.getheader('Content-Type', '').split(';')[0].lower()
        valid_type = (mime in ('text/html', 'application/xhtml+xml') if kind == 'document'
                      else mime in ('image/png', 'image/jpeg', 'image/gif', 'image/webp', 'image/avif')
                      if kind == 'image' else mime in ('video/mp4', 'video/webm', 'video/ogg'))
        if response.status not in (200, 206) or not valid_type:
            raise ValueError('Unsupported upstream response')
        limit = LIMITS[kind]
        if int(response.getheader('Content-Length', '-1')) > limit:
            raise ValueError('Preview exceeds size limit')
        content_range = response.getheader('Content-Range')
        if response.status == 206:
            match = re.fullmatch(r'bytes (\d+)-(\d+)/(\d+)', content_range or '')
            if not match or not (0 <= int(match[1]) <= int(match[2]) < int(match[3]) <= 512 * 1024 * 1024):
                raise ValueError('Invalid upstream range')
        body = bytearray()
        deadline = time.monotonic() + 25
        while len(body) <= limit:
            chunk = response.read(min(65536, limit + 1 - len(body)))
            if not chunk:
                break
            body.extend(chunk)
            if time.monotonic() > deadline:
                raise ValueError('Preview timed out')
        if len(body) > limit:
            raise ValueError('Preview exceeds size limit')
        handler.send_response(response.status)
        handler.send_header('Content-Type', mime)
        handler.send_header('Content-Length', str(len(body)))
        handler.send_header('Access-Control-Allow-Origin', 'https://chat.deltie.net')
        handler.send_header('Access-Control-Expose-Headers', 'Content-Range, Accept-Ranges')
        handler.send_header('Cross-Origin-Resource-Policy', 'cross-origin')
        handler.send_header('X-Content-Type-Options', 'nosniff')
        # Upstream HTML must never become executable on the proxy's origin.
        handler.send_header('Content-Security-Policy', "sandbox; default-src 'none'")
        handler.send_header('Cache-Control', 'public, max-age=300')
        if content_range:
            handler.send_header('Content-Range', content_range)
        if kind == 'video':
            handler.send_header('Accept-Ranges', 'bytes')
        handler.end_headers()
        handler.wfile.write(body)
    except Exception:
        handler._json({'error': 'Preview unavailable or outside supported limits'}, 502)
    finally:
        if connection:
            connection.close()
        SLOTS.release()
