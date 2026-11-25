#!/usr/bin/env python3
"""Update an existing SeND storage module, preserving configuration and data.

Default: preflight only. Use --apply as root, or --rollback BACKUP to restore.
Only the existing Synapse container is restarted. No Compose, pulls or SQL.
"""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import stat
import tempfile
import time

from install_storage import atomic, execute, KNOWN_PREVIEW_MODULES


def digest(value):
    return hashlib.sha256(value).hexdigest()


def inspect(container):
    value = json.loads(execute(['docker', 'inspect', container]))
    if len(value) != 1 or not value[0].get('State', {}).get('Running'):
        raise RuntimeError('The existing Synapse container must be running.')
    value = value[0]
    mounts = [m for m in value.get('Mounts', []) if m.get('Destination') == '/data']
    if len(mounts) != 1 or mounts[0].get('Type') != 'bind':
        raise RuntimeError('Expected one persistent /data bind mount.')
    data = Path(mounts[0]['Source'])
    if not data.is_absolute() or '..' in data.parts or len(data.parts) < 4:
        raise RuntimeError('Expected a specific Synapse data directory.')
    return value, data


def installed(container):
    return execute(['docker', 'exec', container, 'python', '-c',
                    'import sys;sys.stdout.buffer.write(open("/data/send_modules/send_storage.py","rb").read())'])


def healthy(container):
    code = """import urllib.request,urllib.error
with urllib.request.urlopen('http://127.0.0.1:8008/_matrix/client/versions',timeout=3) as r:
 assert r.status==200
try:
 urllib.request.urlopen('http://127.0.0.1:8008/_synapse/client/send/v1/usage',timeout=3)
except urllib.error.HTTPError as e:
 assert e.code==401
else:
 raise RuntimeError('Storage did not enforce authentication')
"""
    for _ in range(30):
        try:
            execute(['docker', 'exec', container, 'python', '-c', code])
            return
        except (RuntimeError, OSError):
            time.sleep(1)
    raise RuntimeError('Synapse did not pass the health/authentication checks.')


def regular_target(path):
    if path.is_symlink() or path.parent.is_symlink() or not path.is_file():
        raise RuntimeError('Expected a regular installed module, without symlinks.')


def restore(container, target, backup, inspection):
    if backup.is_symlink() or not backup.is_dir() or stat.S_IMODE(backup.stat().st_mode) & 0o077:
        raise RuntimeError('Expected the private backup directory created by this script.')
    if backup.stat().st_uid != 0:
        raise RuntimeError('The backup must be owned by root.')
    manifest = backup / 'manifest.json'
    module = backup / 'send_storage.py'
    if manifest.is_symlink() or module.is_symlink():
        raise RuntimeError('Backup files must not be symlinks.')
    saved = json.loads(manifest.read_text())
    old = module.read_bytes()
    if (saved['container'] != inspection['Id'] or saved['image'] != inspection['Image']
            or saved['target'] != str(target) or saved['sha256'] != digest(old)):
        raise RuntimeError('Backup does not match this container/module.')
    regular_target(target)
    atomic(target, old, mode=saved['mode'])
    execute(['docker', 'restart', container])
    healthy(container)
    if installed(container) != old:
        raise RuntimeError('Restored module verification failed.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--container', default='matrix-synapse')
    action = parser.add_mutually_exclusive_group()
    action.add_argument('--apply', action='store_true')
    action.add_argument('--rollback', type=Path)
    args = parser.parse_args()
    if (args.apply or args.rollback) and os.geteuid() != 0:
        parser.error('Run --apply or --rollback with sudo.')
    inspection, data = inspect(args.container)
    if not data.is_absolute() or len(data.parts) < 4:
        raise RuntimeError('Expected a specific persistent Synapse directory.')
    if args.apply or args.rollback:
        lock = os.open(data / '.send-storage-deploy.lock', os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError('Another storage deployment is running.') from None
    target = data / 'send_modules' / 'send_storage.py'
    version = execute(['docker', 'exec', args.container, 'python', '-c',
                       'import synapse;print(synapse.__version__)']).decode().strip()
    if version != '1.159.0':
        raise RuntimeError('Validate this update against the installed Synapse version first.')
    if args.rollback:
        restore(args.container, target, args.rollback.absolute(), inspection)
        print('Restored and verified. Configuration and media were unchanged.')
        return
    old = installed(args.container)
    new = Path(__file__).with_name('send_storage.py').read_bytes()
    compile(new, 'send_storage.py', 'exec')
    if old == new:
        healthy(args.container)
        print('Already installed and healthy. Nothing changed.')
        return
    if digest(old) not in KNOWN_PREVIEW_MODULES:
        raise RuntimeError('Installed module has local changes. Review them before upgrading.')
    healthy(args.container)
    if not args.apply:
        print('Preflight passed. No changes made.')
        print('Apply restarts only Synapse, briefly interrupting connections.')
        print('Configuration, quotas, database and media remain unchanged.')
        return
    regular_target(target)
    if target.read_bytes() != old:
        raise RuntimeError('Installed module changed during preflight.')
    backup = Path(tempfile.mkdtemp(prefix='send-storage-rollback-', dir=data))
    backup.chmod(0o700)
    atomic(backup / 'send_storage.py', old, mode=0o600)
    atomic(backup / 'manifest.json', json.dumps({
        'container': inspection['Id'], 'image': inspection['Image'],
        'target': str(target), 'sha256': digest(old), 'mode': stat.S_IMODE(target.stat().st_mode),
    }).encode(), mode=0o600)
    print('Backup: ' + str(backup), flush=True)
    try:
        # mkdir permissions may have been reduced by an earlier restrictive umask.
        target.parent.chmod(0o755)
        atomic(target, new, mode=0o644)
        execute(['docker', 'restart', args.container])
        healthy(args.container)
        if installed(args.container) != new:
            raise RuntimeError('Installed module verification failed.')
    except BaseException:
        try:
            restore(args.container, target, backup, inspection)
        except BaseException:
            raise RuntimeError('Update and rollback failed. Keep the backup: ' + str(backup)) from None
        raise RuntimeError('Update failed; original module restored and verified. Backup: ' + str(backup)) from None
    print('Installed and verified. No media was deleted.')
    print('Rollback: sudo python3 ' + str(Path(__file__).absolute()) +
          ' --container ' + args.container + ' --rollback ' + str(backup))


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, OSError, ValueError) as error:
        raise SystemExit(str(error)) from None
