#!/usr/bin/env python3
"""Interactive, fresh-host SeND stack installer. Python standard library only."""
import argparse
import getpass
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import re
import secrets
import socket
import subprocess
import sys
from urllib.parse import urlsplit

SOURCE = Path(__file__).resolve().parent
IMAGES = {
    'synapse': 'matrixdotorg/synapse:v1.159.0',
    'postgres': 'postgres:16-alpine',
    'caddy': 'caddy:2.10.2-alpine',
    'livekit': 'livekit/livekit-server:v1.13.1',
    'jwt': 'ghcr.io/element-hq/lk-jwt-service:0.4.4',
    'turn': 'coturn/coturn:4.15.0',
    'ntfy': 'binwiederhier/ntfy:v2.28.0',
}


def domain(value):
    value = value.strip().lower()
    if (len(value) > 253 or '.' not in value or
            not all(re.fullmatch(r'[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?', x)
                    for x in value.split('.'))):
        raise ValueError('Enter a DNS hostname, without https:// or a path.')
    return value


def ask(label, default='', validator=None, private=False):
    while True:
        prompt = f'{label}' + (f' [{default}]' if default else '') + ': '
        value = (getpass.getpass(prompt) if private else input(prompt)).strip() or default
        try:
            return validator(value) if validator else value
        except ValueError as error:
            print(error)


def confirm(label):
    return input(label + ' [y/N]: ').strip().lower() == 'y'


def issuer_url(value):
    url = urlsplit(value)
    if (url.scheme != 'https' or not url.hostname or url.username or url.password
            or url.query or url.fragment):
        raise ValueError('Enter the full HTTPS issuer URL, without credentials or query parameters.')
    return value.rstrip('/')


def email_address(value):
    if not re.fullmatch(r'[A-Za-z0-9_.+%-]+@[A-Za-z0-9.-]+', value):
        raise ValueError('Enter an email address.')
    return value


def write(root, name, value):
    path = root / name
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('x', encoding='utf-8') as stream:
        stream.write(value if isinstance(value, str) else json.dumps(value, indent=2) + '\n')
    path.chmod(0o600)


def generate(root, config, credentials):
    """No subprocesses, network calls or host changes outside a NEW directory."""
    root = Path(root).absolute()
    if root.exists() or root.is_symlink():
        raise ValueError('Destination already exists. Choose a new, private directory.')
    names = {key: domain(config[key]) for key in ('server', 'matrix', 'app', 'rtc', 'turn', 'push')}
    if len(set(names.values())) != len(names):
        raise ValueError('Use a different hostname for each service.')
    ip = ipaddress.IPv4Address(config['ip'])
    if not ip.is_global:
        raise ValueError('A public IPv4 address is required.')
    if not re.fullmatch(r'[A-Za-z0-9_.+%-]+@[A-Za-z0-9.-]+', config['email']):
        raise ValueError('Invalid contact email.')
    subnet = ipaddress.IPv4Network(config['subnet'])
    if not any(subnet.subnet_of(ipaddress.IPv4Network(net)) for net in
               ('10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16')):
        raise ValueError('Use an unused private Docker subnet.')
    root.mkdir(parents=True, mode=0o700)
    origin = 'https://' + names['app']
    random = {key: secrets.token_hex(32) for key in ('db', 'registration', 'macaroon', 'turn', 'livekit')}
    for name, value in credentials.items():
        if '\n' in value or '\r' in value:
            raise ValueError('Credentials must be single-line values.')
        write(root, 'secrets/' + name, value + '\n')
    write(root, 'operator.json', {**config, **names})
    write(root, '.gitignore', '*\n')
    helper_files = ('giphy_proxy.py', 'web_preview.py', 'web_push.py', 'hosting_config.py',
                    'requirements-web-push.txt', 'requirements-conversion.txt')
    for name in helper_files:
        write(root, 'helpers/' + name, (SOURCE / name).read_text())
    write(root, 'helpers/Dockerfile', '''FROM python:3.12-slim-bookworm
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg libcairo2 util-linux ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY requirements-web-push.txt requirements-conversion.txt ./
RUN pip install --no-cache-dir -r requirements-web-push.txt -r requirements-conversion.txt
COPY *.py ./
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
''')
    write(root, 'helpers/init_push.py', '''from pathlib import Path
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives import serialization
import os
path = Path('/state/vapid.pem')
os.umask(0o077)
if not path.exists():
    key = ec.generate_private_key(ec.SECP256R1())
    with path.open('xb') as stream:
        stream.write(key.private_bytes(serialization.Encoding.PEM,
            serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
''')
    synapse = {
        'server_name': names['server'], 'public_baseurl': 'https://' + names['matrix'],
        'pid_file': '/data/homeserver.pid', 'report_stats': False,
        'signing_key_path': '/data/signing.key', 'media_store_path': '/data/media_store',
        'listeners': [{'port': 8008, 'type': 'http', 'tls': False, 'x_forwarded': True,
                       'resources': [{'names': ['client', 'federation'], 'compress': False}]}],
        'database': {'name': 'psycopg2', 'args': {'user': 'synapse', 'password': random['db'],
                    'database': 'synapse', 'host': 'postgres', 'cp_min': 5, 'cp_max': 10}},
        'registration_shared_secret': random['registration'], 'macaroon_secret_key': random['macaroon'],
        'enable_registration': False, 'max_upload_size': '100M',
        'turn_uris': [f"turn:{names['turn']}:3478?transport={x}" for x in ('udp', 'tcp')],
        'turn_shared_secret': random['turn'], 'turn_user_lifetime': '1h', 'turn_allow_guests': False,
        'url_preview_enabled': False,
        'experimental_features': {'msc3266_enabled': True, 'msc4222_enabled': True},
    }
    if config.get('oidc'):
        synapse['oidc_providers'] = [{
            'idp_id': 'oidc', 'idp_name': 'Single sign-on', 'issuer': config['oidc'],
            'client_id': config['oidc_client'], 'client_secret': credentials['oidc-secret'],
            'scopes': ['openid', 'profile'],
            'user_mapping_provider': {'config': {'localpart_template': '{{ user.preferred_username }}',
                                               'display_name_template': '{{ user.name }}'}},
        }]
    if config.get('smtp_host'):
        synapse['email'] = {
            'smtp_host': config['smtp_host'], 'smtp_port': 587,
            'smtp_user': config['smtp_user'], 'smtp_pass': credentials['smtp-password'],
            'require_transport_security': True, 'notif_from': config['email'],
            'app_name': 'SeND', 'enable_notifs': False,
        }
    write(root, 'homeserver.yaml', synapse)
    write(root, 'livekit.yaml', {
        'port': 7880, 'bind_addresses': ['0.0.0.0'],
        'rtc': {'tcp_port': 7881, 'udp_port': 7882, 'use_external_ip': True},
        'keys': {'send': random['livekit']},
    })
    write(root, 'turnserver.conf', f'''listening-port=3478
fingerprint
use-auth-secret
static-auth-secret={random['turn']}
realm={names['server']}
external-ip={ip}
min-port=49160
max-port=49260
no-cli
no-tls
no-dtls
no-multicast-peers
denied-peer-ip=0.0.0.0-0.255.255.255
denied-peer-ip=10.0.0.0-10.255.255.255
denied-peer-ip=127.0.0.0-127.255.255.255
denied-peer-ip=169.254.0.0-169.254.255.255
denied-peer-ip=172.16.0.0-172.31.255.255
denied-peer-ip=192.168.0.0-192.168.255.255
denied-peer-ip=::1
user-quota=12
total-quota=1200
no-tcp-relay
log-file=stdout
''')
    client_discovery = {'m.homeserver': {'base_url': 'https://' + names['matrix']},
                        'org.matrix.msc4143.rtc_foci': [{'type': 'livekit',
                            'livekit_service_url': 'https://' + names['rtc'] + '/jwt'}]}
    write(root, 'discovery/client.json', client_discovery)
    write(root, 'discovery/server.json', {'m.server': names['matrix'] + ':443'})
    # Containers need readable public files; credentials stay private.
    for path in (root / 'discovery').iterdir():
        path.chmod(0o644)
    write(root, 'Caddyfile', f'''{{
    email {config['email']}
}}
{names['server']} {{
    header Access-Control-Allow-Origin "*"
    handle /.well-known/matrix/client {{
        rewrite * /client.json
        root * /discovery
        file_server
    }}
    handle /.well-known/matrix/server {{
        rewrite * /server.json
        root * /discovery
        file_server
    }}
    respond 404
}}
{names['matrix']} {{
    @matrix path /_matrix/* /_synapse/client/*
    reverse_proxy @matrix synapse:8008
    respond 404
}}
{names['rtc']} {{
    handle_path /jwt/* {{
        reverse_proxy jwt:8080
    }}
    handle {{
        reverse_proxy livekit:7880
    }}
}}
{names['push']} {{
    reverse_proxy ntfy:80
}}
{names['app']} {{
    header {{
        Cross-Origin-Opener-Policy same-origin
        Cross-Origin-Embedder-Policy require-corp
        X-Content-Type-Options nosniff
        Referrer-Policy no-referrer
        Cache-Control no-cache
        Content-Security-Policy "default-src 'self'; script-src 'self' 'wasm-unsafe-eval' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' https: blob: data:; media-src 'self' https: blob:; connect-src 'self' https: wss:; worker-src 'self' blob:; font-src 'self' data:; frame-ancestors 'none'; base-uri 'self'; object-src 'none'"
    }}
    handle /auth.html {{
        header Cache-Control no-store
        root * /web/current
        file_server
    }}
    @push path /api/push/* /_matrix/push/v1/notify
    handle @push {{
        request_body {{
            max_size 64KB
        }}
        reverse_proxy web-push:8141
    }}
    handle /api/servers/* {{
        reverse_proxy media:8091
    }}
    handle /api/* {{
        respond 404
    }}
    @assets path *.js *.wasm *.json *.png *.ico *.woff *.woff2
    handle @assets {{
        root * /web/current
        file_server
    }}
    handle {{
        root * /web/current
        try_files {{path}} /index.html
        file_server
    }}
}}
''')
    def service(image, **kwargs):
        return {'image': image, 'restart': 'unless-stopped', **kwargs}
    common = {'SEND_APP_ORIGIN': origin, 'TRUSTED_PROXY_CIDRS': config['subnet']}
    services = {
        'postgres': service(IMAGES['postgres'], environment={
            'POSTGRES_USER': 'synapse', 'POSTGRES_DB': 'synapse', 'POSTGRES_PASSWORD': random['db'],
            'POSTGRES_INITDB_ARGS': '--encoding=UTF8 --locale=C'},
            volumes=['database:/var/lib/postgresql/data'],
            healthcheck={'test': ['CMD-SHELL', 'pg_isready -U synapse'], 'interval': '5s', 'retries': 20}),
        'synapse': service(IMAGES['synapse'], user='0:0',
            entrypoint=['sh', '-c', 'cp /config/homeserver.yaml /data/homeserver.yaml && chown 991:991 /data /data/homeserver.yaml && exec /start.py'],
            environment={'SYNAPSE_CONFIG_PATH': '/data/homeserver.yaml'},
            volumes=['./homeserver.yaml:/config/homeserver.yaml:ro', 'matrix-data:/data'],
            depends_on={'postgres': {'condition': 'service_healthy'}}),
        'livekit': service(IMAGES['livekit'], command=['--config', '/config.yaml'],
            volumes=['./livekit.yaml:/config.yaml:ro'], ports=['7881:7881/tcp', '7882:7882/udp']),
        'jwt': service(IMAGES['jwt'], environment={
            'LIVEKIT_URL': 'wss://' + names['rtc'], 'LIVEKIT_KEY': 'send',
            'LIVEKIT_SECRET': random['livekit'], 'LIVEKIT_FULL_ACCESS_HOMESERVERS': names['server']}),
        'turn': service(IMAGES['turn'], user='0:0', network_mode='host',
            command=['-c', '/etc/coturn/turnserver.conf'],
            volumes=['./turnserver.conf:/etc/coturn/turnserver.conf:ro']),
        'media': service('send-helpers:local', build='./helpers',
            command=['python', 'giphy_proxy.py'], volumes=['./secrets:/secrets:ro'],
            environment={**common, 'HOST': '0.0.0.0', 'PORT': '8091',
                'KLIPY_API_KEY_FILE': '/secrets/klipy-key', 'TELEGRAM_BOT_TOKEN_FILE': '/secrets/telegram-token'}),
        'web-push': service('send-helpers:local', build='./helpers', volumes=['push-data:/state'],
            command=['sh', '-c', 'python init_push.py && exec gunicorn --workers 1 --threads 4 --timeout 45 --bind 0.0.0.0:8141 web_push:app'],
            environment={**common, 'WEB_PUSH_STATE': '/state', 'WEB_PUSH_PRIVATE_KEY': '/state/vapid.pem',
                         'WEB_PUSH_CONTACT': 'mailto:' + config['email'], 'WEB_PUSH_QUEUE': '1',
                         'WEB_PUSH_ISSUERS': json.dumps({names['server']: 'https://' + names['matrix']})}),
        'ntfy': service(IMAGES['ntfy'], command=['serve'], volumes=['ntfy-data:/var/cache/ntfy'],
            environment={'NTFY_BASE_URL': 'https://' + names['push'], 'NTFY_BEHIND_PROXY': 'true',
                         'NTFY_CACHE_FILE': '/var/cache/ntfy/cache.db',
                         'NTFY_ATTACHMENT_TOTAL_SIZE_LIMIT': '0', 'NTFY_ENABLE_LOGIN': 'false'}),
        'caddy': service(IMAGES['caddy'], ports=['80:80', '443:443'], volumes=[
            './Caddyfile:/etc/caddy/Caddyfile:ro', './discovery:/discovery:ro', './web:/web:ro',
            'caddy-data:/data', 'caddy-config:/config']),
    }
    for name, spec in services.items():
        spec['logging'] = {'driver': 'json-file', 'options': {'max-size': '10m', 'max-file': '3'}}
        if name != 'turn':
            spec['networks'] = ['send']
    for name in ('media', 'web-push'):
        services[name]['cap_drop'] = ['ALL']
        services[name]['security_opt'] = ['no-new-privileges:true']
    write(root, 'compose.yaml', {'name': 'send', 'services': services,
        'networks': {'send': {'ipam': {'config': [{'subnet': config['subnet']}]}}},
        'volumes': {name: {} for name in ('database', 'matrix-data', 'push-data', 'ntfy-data', 'caddy-data', 'caddy-config')}})
    (root / 'web').mkdir()
    write(root, 'client-defines.json', {
        'GIF_PROXY_URL': origin + '/api/servers/klipy/search',
        'TELEGRAM_STICKER_PROXY_URL': origin + '/api/servers/telegram/stickers',
        'WEB_PREVIEW_PROXY_URL': origin + '/api/servers/preview',
    })
    write(root, 'deploy-web.py', (SOURCE.parent / 'packaging/deploy-web.py').read_text())
    return root


def install_web(root, archive, checksum):
    archive = Path(archive).resolve(strict=True)
    if not re.fullmatch(r'[0-9a-fA-F]{64}', checksum):
        raise ValueError('Provide the SHA-256 from the trusted release manifest.')
    with archive.open('rb') as stream:
        if hashlib.file_digest(stream, 'sha256').hexdigest() != checksum.lower():
            raise ValueError('PWA checksum mismatch; nothing deployed.')
    match = re.fullmatch(r'SeND-(\d+\.\d+\.\d+\+\d+)-web.tar.gz', archive.name)
    if not match:
        raise ValueError('Use the original SeND web release archive filename.')
    subprocess.run([sys.executable, str(root / 'deploy-web.py'), str(archive),
                    str(root / 'web'), match[1]], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, default=Path('/opt/send'))
    args = parser.parse_args()
    os.umask(0o077)
    print('SeND server setup, for a NEW dedicated Linux host. Existing servers are not migrated.\n'
          'Docker Engine and Compose v2 must be installed. DNS must point directly here.\n'
          'This creates private configuration, then asks before starting any services.\n'
          'Never change the Matrix server name after creating accounts.\n')
    if sys.platform != 'linux':
        raise ValueError('Run this installer on Linux.')
    subprocess.run(['docker', 'compose', 'version'], check=True)
    for command in (
        ['docker', 'ps', '-aq', '--filter', 'label=com.docker.compose.project=send'],
        ['docker', 'volume', 'ls', '-q', '--filter', 'label=com.docker.compose.project=send'],
    ):
        if subprocess.check_output(command, text=True).strip():
            raise ValueError('An existing send Compose project was found. Use its update procedure, not this installer.')
    if args.directory.exists():
        raise ValueError('Destination exists. This installer will not overwrite it.')
    config = {'server': ask('Matrix server name (user@this-domain)', validator=domain)}
    for key, prefix in [('matrix', 'matrix'), ('app', 'chat'), ('rtc', 'rtc'), ('turn', 'turn'), ('push', 'push')]:
        config[key] = ask(key.capitalize() + ' hostname', prefix + '.' + config['server'], domain)
    config['ip'] = ask('Server public IPv4 address', validator=lambda v: str(ipaddress.IPv4Address(v)))
    config['email'] = ask('Email for TLS expiry and push contact', validator=email_address)
    config['subnet'] = ask('Unused Docker IPv4 subnet', '172.29.125.0/24', lambda v: str(ipaddress.IPv4Network(v)))
    print('Provider keys stay on this server. Blank disables the corresponding feature.\n'
          'Create a dedicated Telegram bot through @BotFather; it imports public packs only.\n'
          'Request a KLIPY API key and follow its attribution and usage terms.')
    credentials = {'telegram-token': ask('Telegram bot token', private=True),
                   'klipy-key': ask('KLIPY API key', private=True)}
    if confirm('Configure an existing OpenID Connect identity provider?'):
        config['oidc'] = ask('OIDC issuer URL', validator=issuer_url)
        config['oidc_client'] = ask('OIDC client ID')
        credentials['oidc-secret'] = ask('OIDC client secret', private=True)
        print('Register this callback at the provider: https://' + config['matrix'] + '/_synapse/client/oidc/callback')
    if confirm('Configure email verification/password reset through SMTP STARTTLS on port 587?'):
        config['smtp_host'] = ask('SMTP hostname', validator=domain)
        config['smtp_user'] = ask('SMTP username')
        credentials['smtp-password'] = ask('SMTP password', private=True)
        print('The SMTP account must allow sending from ' + config['email'])
    print('Required inbound ports: TCP 80,443,3478,7881; UDP 3478,7882,49160-49260.\n'
          'No firewall or DNS changes will be made. The ntfy service uses unguessable public\n'
          'topics for UnifiedPush; do not use it for plaintext private notifications.\n'
          'TURN/TCP is provided, but TURN-over-TLS on 443 is not; some restricted networks need it.')
    if not confirm('Generate this stack in ' + str(args.directory) + '?'):
        return
    root = generate(args.directory, config, credentials)
    print('Configuration written. Keep the entire directory private and back it up securely.')
    archive = ask('Path to the downloaded SeND web release .tar.gz (blank skips deployment)')
    if archive:
        install_web(root, archive, ask('SHA-256 from its release manifest'))
    else:
        print('No PWA deployed. Use deploy-web.py with a checksum-verified release before opening the app.')
    if not confirm('Build containers and start the stack now?'):
        return
    for key in ('server', 'matrix', 'app', 'rtc', 'turn', 'push'):
        host = config[key]
        if config['ip'] not in socket.gethostbyname_ex(host)[2]:
            raise ValueError('DNS does not point to this server: ' + host)
    for port in (80, 443, 3478, 7881):
        with socket.socket() as sock:
            sock.bind(('0.0.0.0', port))
    command = ['docker', 'compose', '--project-directory', str(root)]
    subprocess.run(command + ['config', '--quiet'], check=True)
    subprocess.run(command + ['build'], check=True)
    subprocess.run(command + ['run', '--rm', '--no-deps', 'caddy', 'caddy', 'validate', '--config', '/etc/caddy/Caddyfile'], check=True)
    subprocess.run(command + ['up', '-d', '--wait', '--wait-timeout', '180'], check=True)
    if confirm('Create the first Matrix administrator now?'):
        subprocess.run(command + ['exec', 'synapse', 'register_new_matrix_user',
            '-c', '/config/homeserver.yaml', 'http://localhost:8008', '--admin'], check=True)
    print('Containers started. Before inviting users, run the checks in server/INSTALL.md.\n'
          'A running container is not a verified call, encrypted message, or iOS notification.')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print('Setup stopped: ' + str(error), file=sys.stderr)
        print('Existing configuration and volumes were not deleted. Inspect before retrying.', file=sys.stderr)
        sys.exit(1)
