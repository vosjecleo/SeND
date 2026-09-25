#!/usr/bin/env python3
"""Build with CI Last.fm app credentials without logging values or argv secrets.

Like any distributed Last.fm client, the resulting binary contains the app
credentials. These are not user session tokens. Never put session tokens here.
Local/PR builds may omit credentials; main-branch CI releases must supply them.
"""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


def main():
    key = os.environ.get('LASTFM_API_KEY', '')
    secret = os.environ.get('LASTFM_API_SECRET', '')
    required = os.environ.get('GITHUB_REF') == 'refs/heads/main'
    valid = all(re.fullmatch(r'[a-fA-F0-9]{32}', value) for value in (key, secret))
    if (key or secret or required) and not valid:
        raise SystemExit('Set both LASTFM_API_KEY and LASTFM_API_SECRET repository secrets before releasing.')
    flutter = shutil.which('flutter')
    if not flutter:
        raise SystemExit('Flutter is not on PATH')
    with tempfile.TemporaryDirectory(prefix='send-build-') as directory:
        args = [flutter, *sys.argv[1:]]
        if valid:
            config = Path(directory) / 'defines.json'
            fd = os.open(config, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(fd, 'w') as stream:
                json.dump({'LASTFM_API_KEY': key, 'LASTFM_API_SECRET': secret,
                           'LASTFM_PUBLIC_DISPLAY_APPROVED': True}, stream)
            args.append('--dart-define-from-file=' + str(config))
        env = {k: v for k, v in os.environ.items() if k not in ('LASTFM_API_KEY', 'LASTFM_API_SECRET')}
        return subprocess.call(args, env=env)


if __name__ == '__main__':
    sys.exit(main())
