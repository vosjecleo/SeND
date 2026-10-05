#!/usr/bin/env bash
# Gateway-only update. Retains VAPID keys, subscription DB, service and nginx.
set -euo pipefail
[[ $EUID == 0 ]] || { echo 'Run with sudo.' >&2; exit 1; }
stage="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
target=/opt/deltiecord-web-push/web_push.py
[[ -f "$target" && ! -L "$target" && -f "$stage/web_push.py" ]]
(cd -- "$stage" && sha256sum --check --strict SHA256SUMS)
/opt/deltiecord-web-push/venv/bin/python -c \
  'import ast,sys; ast.parse(open(sys.argv[1]).read())' "$stage/web_push.py"
backup="$(mktemp -d /opt/deltiecord-web-push/preview-rollback.XXXXXXXX)"
cp -p -- "$target" "$backup/web_push.py"
rollback() {
  cp -p -- "$backup/web_push.py" "$target"
  systemctl restart deltiecord-web-push
  echo "Gateway rolled back from $backup" >&2
}
trap rollback ERR
install -o root -g root -m 0644 -- "$stage/web_push.py" "$target"
systemctl restart deltiecord-web-push
for attempt in {1..15}; do
  if systemctl is-active --quiet deltiecord-web-push && \
      curl -fsS http://127.0.0.1:8141/api/push/config >/dev/null; then
    trap - ERR
    echo "Declarative gateway installed; rollback retained at $backup"
    exit 0
  fi
  sleep 1
done
false
