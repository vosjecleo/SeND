#!/usr/bin/env python3
"""Produce reviewed candidates; never overwrite live nginx/contact API files."""
from pathlib import Path
import argparse
import hashlib


def replace_once(text, old, new):
    if text.count(old) != 1:
        raise ValueError('Live configuration differs from the inspected layout; review manually')
    return text.replace(old, new, 1)


def prepare(output):
    output = Path(output)
    output.mkdir(mode=0o700, parents=True, exist_ok=True)
    nginx = Path('/etc/nginx/sites-enabled/matrix')
    api = Path('/srv/storage/services/contact-api/app.py')
    original = nginx.read_text()
    old = '''    location / {
        proxy_pass http://127.0.0.1:8089;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }'''
    changed = replace_once(original, old, '    include /etc/nginx/snippets/deltiecord-chat.conf;')
    (output / 'matrix.candidate').write_text(changed)
    (output / 'matrix.before.sha256').write_text(hashlib.sha256(nginx.read_bytes()).hexdigest())
    original = api.read_text()
    changed = replace_once(original, 'import deltiecord_media_proxy',
        'os.environ.setdefault("KLIPY_API_KEY_FILE", "/srv/storage/services/contact-api/klipy-api-key")\nimport deltiecord_media_proxy')
    changed = replace_once(changed, '            "/api/servers/telegram/stickers",',
        '            "/api/servers/klipy/search",\n            "/api/servers/telegram/stickers",')
    compile(changed, 'app.candidate.py', 'exec')
    (output / 'app.candidate.py').write_text(changed)
    (output / 'app.before.sha256').write_text(hashlib.sha256(api.read_bytes()).hexdigest())
    index = Path('/srv/storage/www/deltie/cord/index.html')
    original = index.read_text()
    changed = replace_once(original, '      <div class="download-grid">',
        '      <p><a href="https://chat.deltie.net">Open SeND Web</a> '
        '— install on iPhone/iPad, Android or desktop. '
        'iOS notifications require Home Screen installation and iOS 16.4+.</p>\n'
        '      <div class="download-grid">\n'
        '        <details class="download-card" data-platform="web"><summary>Web / PWA</summary><div class="download-body">Loading releases...</div></details>')
    (output / 'index.candidate.html').write_text(changed)
    (output / 'index.before.sha256').write_text(hashlib.sha256(index.read_bytes()).hexdigest())
    javascript = Path('/srv/storage/www/deltie/cord/cord.js')
    changed = replace_once(javascript.read_text(), '["windows", "linux", "android"]',
                           '["windows", "linux", "android", "web"]')
    (output / 'cord.candidate.js').write_text(changed)
    (output / 'cord.before.sha256').write_text(hashlib.sha256(javascript.read_bytes()).hexdigest())
    print('Candidates prepared; inspect the diffs before installing. No live files changed.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('output')
    prepare(parser.parse_args().output)
