#!/usr/bin/env bash
# Apply only the two reviewed pack-size bounds to the existing media service.
set -euo pipefail
[[ $EUID == 0 ]] || { echo 'Run this script with sudo.' >&2; exit 1; }
target=/srv/storage/services/contact-api/deltiecord_media_proxy.py
service=contact-api.service
[[ -f "$target" && ! -L "$target" ]] || exit 1
systemctl is-active --quiet "$service"
backup="$(mktemp -d /srv/storage/services/contact-api/media-limit-110.XXXXXXXX)"
cp -p -- "$target" "$backup/original.py"
python3 - "$target" "$backup/candidate.py" <<'PY'
import ast
import pathlib
import sys
source = pathlib.Path(sys.argv[1]).read_text()
pairs = [('len(stickers) > 120:', 'len(stickers) > 150:'),
         ('index < 0 or index >= 120:', 'index < 0 or index >= 150:')]
for old, new in pairs:
    if source.count(old) == 1 and new not in source:
        source = source.replace(old, new, 1)
    elif old not in source and source.count(new) == 1:
        pass
    else:
        raise SystemExit('Unexpected media helper; no live file changed.')
ast.parse(source)
pathlib.Path(sys.argv[2]).write_text(source)
PY
if cmp -s "$target" "$backup/candidate.py"; then
  echo 'Pack limit already set to 150; no restart needed.'
  exit 0
fi
rollback() {
  cp -p -- "$backup/original.py" "$target"
  systemctl restart "$service"
  echo "Update failed; original restored from $backup" >&2
}
trap rollback ERR
install -o cleo -g cleo -m 0644 "$backup/candidate.py" "$target"
systemctl restart "$service"
sleep 2
systemctl is-active --quiet "$service"
trap - ERR
echo "Telegram pack limit updated to 150. Rollback: $backup/original.py"
