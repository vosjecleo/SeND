#!/usr/bin/env bash
# Run from a reviewed staging directory containing web_push.py and SHA256SUMS.
# Updates the Web Push worker/unit and one exact chat.deltie.net push route.
# Refuses to overwrite files changed since staging; retains rollback copies.
set -euo pipefail
[[ "$EUID" -eq 0 ]] || { echo 'Run this script with sudo.' >&2; exit 1; }
stage="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
target=/opt/deltiecord-web-push/web_push.py
service=deltiecord-web-push.service
unit=/etc/systemd/system/deltiecord-web-push.service
nginx=/etc/nginx/snippets/deltiecord-chat.conf
[[ -f "$target" && ! -L "$target" && -f "$stage/web_push.py" && ! -L "$stage/web_push.py" ]]
cd "$stage"
sha256sum --check --strict SHA256SUMS
sha256sum --check --strict CURRENT-SHA256SUMS
backup="$(mktemp -d /opt/deltiecord-web-push/update-108.XXXXXXXX)"
chmod 0700 "$backup"
cp -- "$target" "$backup/web_push.py"
cp -- "$unit" "$backup/service.before"
cp -- "$nginx" "$backup/nginx.before"
install -m 0644 -o root -g root "$stage/web_push.py" "$backup/candidate.py"
/opt/deltiecord-web-push/venv/bin/python -m py_compile "$backup/candidate.py"
restore() {
  install -m 0644 -o root -g root "$backup/web_push.py" "$target"
  install -m 0644 -o root -g root "$backup/service.before" "$unit"
  install -m 0644 -o root -g root "$backup/nginx.before" "$nginx"
  systemctl daemon-reload
  systemctl restart "$service"
  nginx -t && systemctl reload nginx
  echo "Update failed; previous worker restored from $backup" >&2
}
trap restore ERR
install -m 0644 -o root -g root "$backup/candidate.py" "$target"
install -m 0644 -o root -g root "$stage/web-push-service.candidate" "$unit"
install -m 0644 -o root -g root "$stage/chat-nginx.candidate" "$nginx"
nginx -t
systemctl daemon-reload
systemctl restart "$service"
curl --fail --silent --show-error --retry 5 --retry-connrefused --retry-delay 1 \
  http://127.0.0.1:8141/api/push/config >/dev/null
systemctl is-active --quiet "$service"
systemctl reload nginx
status="$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
  --resolve chat.deltie.net:443:127.0.0.1 -H 'Content-Type: application/json' \
  --data '{}' https://chat.deltie.net/_matrix/push/v1/notify)"
[[ "$status" == 400 ]]
trap - ERR
echo "Web Push and exact gateway route updated. Rollback copies: $backup"
