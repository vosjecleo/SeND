#!/usr/bin/env python3
"""Extract a verified web release, then atomically select it. No service edits."""
import hashlib
import json
import os
import pathlib
import re
import shutil
import sys
import tarfile
import tempfile


def deploy(archive, root, release):
    if not re.fullmatch(r'\d+\.\d+\.\d+\+\d+', release):
        raise ValueError('Invalid release identifier')
    root = pathlib.Path(root).resolve()
    if root in (pathlib.Path('/'), pathlib.Path.home()):
        raise ValueError('Refusing broad deployment root')
    root.mkdir(parents=True, exist_ok=True)
    destination = root / release
    with open(archive, 'rb') as source:
        digest = hashlib.file_digest(source, 'sha256').hexdigest()
    if destination.exists():
        if (destination / '.archive-sha256').read_text().strip() != digest:
            raise ValueError('Refusing to replace an existing different release')
    else:
        with tempfile.TemporaryDirectory(prefix='.stage-', dir=root) as staging:
            staging = pathlib.Path(staging)
            with tarfile.open(archive, 'r:gz') as bundle:
                members = bundle.getmembers()
                if len(members) > 10000 or sum(member.size for member in members) > 256 * 1024 * 1024:
                    raise ValueError('Web archive exceeds deployment limits')
                for member in members:
                    name = pathlib.PurePosixPath(member.name)
                    if name.is_absolute() or '..' in name.parts or not (member.isfile() or member.isdir()):
                        raise ValueError('Unsafe web archive member')
                # Debian's Python 3.11 lacks tarfile's data filter. Extract only
                # the regular members validated above, never archive permissions,
                # links or devices. Exclusive creation rejects duplicate files.
                for member in members:
                    target = staging / member.name
                    if member.isdir():
                        target.mkdir(parents=True, exist_ok=True)
                    else:
                        target.parent.mkdir(parents=True, exist_ok=True)
                        with bundle.extractfile(member) as source, target.open('xb') as output:
                            shutil.copyfileobj(source, output)
                        target.chmod(0o644)
            for name in ['index.html', 'main.dart.js', 'sw.js', 'browser_bridge.js', 'pkg/vodozemac_bindings_dart_bg.wasm']:
                if not (staging / name).is_file():
                    raise ValueError('Incomplete web release: ' + name)
            info = json.loads((staging / 'version.json').read_text())
            if f"{info['version']}+{info['build_number']}" != release:
                raise ValueError('Web archive version mismatch')
            # Nginx needs to traverse immutable release directories.
            staging.chmod(0o755)
            (staging / '.archive-sha256').write_text(digest + '\n')
            staging.rename(destination)
    link = root / ('.current-' + release)
    if link.exists() or link.is_symlink():
        raise ValueError('A deployment is already staged')
    link.symlink_to(destination.name, target_is_directory=True)
    os.replace(link, root / 'current')
    print('Web release selected: ' + release)


if __name__ == '__main__':
    if len(sys.argv) != 4:
        raise SystemExit('usage: deploy-web.py ARCHIVE ROOT VERSION+BUILD')
    deploy(*sys.argv[1:])
