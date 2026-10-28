#!/usr/bin/env python3
"""Install SeND storage on an existing Docker Compose Synapse 1.159 stack.

Read-only unless --apply or --rollback is supplied. Run from this source bundle.
Only Synapse is recreated. PostgreSQL, nginx, certificates and media stay put.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile
import time

SOURCE = Path(__file__).resolve().parent


def execute(args, data=None):
    result = subprocess.run(args, input=data, capture_output=True, timeout=90)
    if result.returncode:
        raise RuntimeError('A configuration or container check failed. Run setup with permission to read this Compose stack. No command output or credentials were logged.')
    return result.stdout


def atomic(path, data, mode=None):
    old = path.stat() if path.exists() else None
    descriptor, temporary = tempfile.mkstemp(prefix='.send-storage-', dir=path.parent)
    try:
        with os.fdopen(descriptor, 'wb') as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, mode if mode is not None else stat.S_IMODE(old.st_mode) if old else 0o600)
        if old:
            os.chown(temporary, old.st_uid, old.st_gid)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compose', required=True, type=Path)
    parser.add_argument('--data', type=Path, help='Host directory mounted at /data; discovered from Docker if omitted')
    parser.add_argument('--config', type=Path, help='Host homeserver.yaml when mounted separately')
    parser.add_argument('--service', default='synapse')
    parser.add_argument('--database-service', default='postgres')
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--rollback', type=Path)
    args = parser.parse_args()
    compose = args.compose.absolute()
    if (compose.is_symlink() or not compose.is_file() or args.apply and args.rollback):
        parser.error('Supply the real Compose file and a specific Synapse data directory.')
    base = ['docker', 'compose', '--project-directory', str(compose.parent), '-f', str(compose)]
    services = execute(base + ['config', '--services']).decode().splitlines()
    if args.service not in services or args.database_service not in services:
        parser.error('Synapse/database service does not belong to this Compose stack.')
    container = execute(base + ['ps', '-q', args.service]).decode().strip()
    if not container:
        parser.error('Start the existing Synapse service before running setup checks.')
    inspection = json.loads(execute(['docker', 'inspect', container]))[0]
    mounts = inspection.get('Mounts', [])
    data_mount = next((m for m in mounts if m.get('Destination') == '/data'), None)
    if data_mount is None:
        parser.error('This stack has no persistent /data mount.')
    data = args.data.absolute() if args.data else Path(data_mount['Source']).absolute()
    if data.is_symlink() or not data.is_dir() or len(data.parts) < 4:
        parser.error('Expected a specific persistent Synapse data directory.')
    hs = args.config.absolute() if args.config else data / 'homeserver.yaml'
    module = data / 'send_modules' / 'send_storage.py'
    if hs.is_symlink() or not hs.is_file() or module.is_symlink() or module.parent.is_symlink():
        parser.error('Expected regular configuration/module files, without symlinks.')
    if module.exists() and module.read_bytes() != (SOURCE / 'send_storage.py').read_bytes():
        parser.error('An existing storage adapter differs from this bundle. Review it instead of overwriting it.')
    if hs.parent != data and not any(Path(m.get('Source', '')).resolve() == hs.resolve()
                                    and m.get('Destination') in ('/config/homeserver.yaml','/data/homeserver.yaml') for m in mounts):
        parser.error('The configuration is not mounted by this Synapse container.')
    if not any(m.get('Destination') == '/data' and Path(m['Source']).resolve() == data.resolve()
               for m in inspection.get('Mounts', [])):
        parser.error('The supplied data directory is not this Synapse container’s /data bind mount.')
    version = execute(base + ['exec', '-T', args.service, 'python', '-c',
                             'import synapse;print(synapse.__version__)']).decode().strip()
    if version != '1.159.0':
        parser.error('This adapter is tested with Synapse 1.159.0. Validate it against your version before installing.')

    def sql(value):
        return execute(base + ['exec', '-T', args.database_service, 'sh', '-c',
            'exec psql -X -U "${POSTGRES_USER:-postgres}" -d "${POSTGRES_DB:-synapse}" -v ON_ERROR_STOP=1 -Atq'], value.encode()).decode().strip()

    def restart():
        execute(base + ['up', '-d', '--no-deps', '--pull', 'never', args.service])

    def restore(backup):
        backup = backup.absolute()
        if backup.is_symlink() or not backup.is_dir() or stat.S_IMODE(backup.stat().st_mode) & 0o077:
            raise RuntimeError('Rollback requires the private backup directory created by this installer.')
        saved = json.loads((backup / 'targets.json').read_text())
        if saved['compose'] != str(compose) or saved['data'] != str(data) or saved['config'] != str(hs):
            raise RuntimeError('Backup belongs to another stack.')
        atomic(compose, (backup / 'compose.yaml').read_bytes())
        atomic(hs, (backup / 'homeserver.yaml').read_bytes())
        # Keep classification records. Only remove the new admission trigger;
        # never delete media or tables as part of rollback.
        sql('DROP TRIGGER IF EXISTS send_storage_quota ON local_media_repository;')
        restart()

    if args.rollback:
        restore(args.rollback)
        print('Original Synapse/Compose configuration restored. Stored media and classification records were retained.')
        return
    # Verify the DB role points at a Synapse database without reading user data.
    sql('SELECT 1 FROM local_media_repository LIMIT 0;')
    installed = sql("SELECT to_regclass('send_storage_policy') IS NOT NULL;") == 't'
    if not args.apply:
        print('Checks passed. Apply will add SeND’s authenticated storage/profile API and 12 GiB original-upload allowance, retaining existing media. Only Synapse will be recreated.')
        print('No configuration or database changes made. Use --apply during a maintenance window after preview testing.')
        return
    if installed:
        parser.error('Storage tables already exist. Do not overwrite an existing installation; use its validated update/rollback procedure.')

    backup = Path(tempfile.mkdtemp(prefix='send-storage-rollback-133-', dir=compose.parent))
    backup.chmod(0o700)
    for source, name in [(compose, 'compose.yaml'), (hs, 'homeserver.yaml')]:
        shutil.copy2(source, backup / name)
        (backup / name).chmod(0o600)
    (backup / 'targets.json').write_text(json.dumps({'compose': str(compose), 'data': str(data), 'config': str(hs)}))
    (backup / 'targets.json').chmod(0o600)
    # Use the existing image's YAML parser. Output is captured privately, never
    # printed: Compose and homeserver configuration may contain credentials.
    modify = '''import json,sys,yaml
p=json.load(sys.stdin)
c=yaml.safe_load(p['compose']);h=yaml.safe_load(p['homeserver'])
s=c['services'][p['service']]; e=s.get('environment') or {}
if isinstance(e,list):e={v.partition('=')[0]:(v.partition('=')[2] if '=' in v else None) for v in e}
old=e.get('PYTHONPATH') or ''
if '/data/send_modules' not in old.split(':'):e['PYTHONPATH']='/data/send_modules'+(':'+old if old else '')
s['environment']=e
m=h.setdefault('modules',[])
if not any(v.get('module')=='send_storage.SendStorage' for v in m):m.append({'module':'send_storage.SendStorage','config':{}})
print(json.dumps({'compose':yaml.safe_dump(c,sort_keys=False),'homeserver':yaml.safe_dump(h,sort_keys=False)}))
'''
    payload = json.dumps({'compose': compose.read_text(), 'homeserver': hs.read_text(), 'service': args.service}).encode()
    changed = json.loads(execute(base + ['exec', '-T', args.service, 'python', '-c', modify], payload))
    try:
        module.parent.mkdir(mode=0o755, exist_ok=True)
        atomic(module, (SOURCE / 'send_storage.py').read_bytes(), mode=0o644)
        atomic(hs, changed['homeserver'].encode())
        atomic(compose, changed['compose'].encode())
        execute(base + ['config', '--quiet'])
        sql('BEGIN;\n' + (SOURCE / 'storage_schema.sql').read_text() + '\nCOMMIT;')
        restart()
        probe = "import urllib.request,urllib.error\ntry:urllib.request.urlopen('http://127.0.0.1:8008/_synapse/client/send/v1/usage',timeout=3)\nexcept urllib.error.HTTPError as e:assert e.code==401\nelse:raise RuntimeError('Storage endpoint did not enforce authentication')"
        healthy = False
        for _ in range(20):
            try:
                execute(base + ['exec', '-T', args.service, 'python', '-c', probe])
                healthy = True
                break
            except RuntimeError:
                time.sleep(1)
        if not healthy:
            raise RuntimeError('The storage endpoint did not pass its health/authentication check.')
    except Exception:
        restore(backup)
        raise RuntimeError('Installation failed and original configuration was restored. The private backup is ' + str(backup)) from None
    print('SeND storage installed. Existing media was retained. Private rollback directory: ' + str(backup))
    print('Ensure the public reverse proxy forwards /_synapse/client/send/v1/ to Synapse before enabling client controls. No nginx or certificate changes were made.')


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, OSError, ValueError) as error:
        raise SystemExit(str(error)) from None
