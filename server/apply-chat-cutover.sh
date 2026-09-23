#!/usr/bin/env bash
# Run manually with sudo AFTER reviewing the generated candidate diffs.
set -euo pipefail
[[ "$EUID" -eq 0 ]] || { echo 'Run with sudo.' >&2; exit 1; }
stage="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
nginx_target="$(readlink -f /etc/nginx/sites-enabled/matrix)"
api_root=/srv/storage/services/contact-api
site_root=/srv/storage/www/deltie/cord
[[ "$(sha256sum "$nginx_target" | cut -d' ' -f1)" == "$(<"$stage/candidates/matrix.before.sha256")" ]]
[[ "$(sha256sum "$api_root/app.py" | cut -d' ' -f1)" == "$(<"$stage/candidates/app.before.sha256")" ]]
[[ "$(sha256sum "$site_root/index.html" | cut -d' ' -f1)" == "$(<"$stage/candidates/index.before.sha256")" ]]
[[ "$(sha256sum "$site_root/cord.js" | cut -d' ' -f1)" == "$(<"$stage/candidates/cord.before.sha256")" ]]
[[ -s /srv/storage/www/deltiecord-web/current/main.dart.js ]]
[[ -s "$stage/klipy-api-key" && "$(stat -c '%a' "$stage/klipy-api-key")" == 600 ]]
command -v openssl >/dev/null
command -v nginx >/dev/null

backup="/srv/storage/releases-archive/deltiecord/server-cutover-$(date -u +%Y%m%dT%H%M%SZ)"
install -d -m 0700 "$backup"
printf 'Rollback backup directory: %s\n' "$backup"
cp -p -- "$nginx_target" "$backup/matrix"
cp -p -- "$api_root/app.py" "$api_root/deltiecord_media_proxy.py" "$backup/"
cp -p -- "$site_root/index.html" "$site_root/cord.js" "$backup/"
if [[ -f "$api_root/klipy-api-key" ]]; then
  cp -p -- "$api_root/klipy-api-key" "$backup/klipy-api-key"
fi

if ! id deltiecord-push >/dev/null 2>&1; then
  useradd --system --user-group --home-dir /var/lib/deltiecord-web-push --shell /usr/sbin/nologin deltiecord-push
fi
install -d -m 0755 /opt/deltiecord-web-push
install -m 0644 "$stage/web_push.py" "$stage/giphy_proxy.py" "$stage/requirements-web-push.txt" /opt/deltiecord-web-push/
python3 -m venv /opt/deltiecord-web-push/venv
/opt/deltiecord-web-push/venv/bin/pip install --disable-pip-version-check -r /opt/deltiecord-web-push/requirements-web-push.txt
install -d -o deltiecord-push -g deltiecord-push -m 0700 /var/lib/deltiecord-web-push
if [[ ! -e /var/lib/deltiecord-web-push/vapid.pem ]]; then
  (umask 077; openssl ecparam -name prime256v1 -genkey -noout -out /var/lib/deltiecord-web-push/vapid.pem)
  chown deltiecord-push:deltiecord-push /var/lib/deltiecord-web-push/vapid.pem
fi
install -m 0644 "$stage/deltiecord-web-push.service" /etc/systemd/system/
install -m 0644 "$stage/chat-nginx.conf" /etc/nginx/snippets/deltiecord-chat.conf
install -m 0644 "$stage/candidates/matrix.candidate" "$nginx_target"
if ! nginx -t; then
  cp -p -- "$backup/matrix" "$nginx_target"
  echo "Nginx configuration restored. Review $backup before retrying." >&2
  exit 1
fi
install -o cleo -g cleo -m 0600 "$stage/klipy-api-key" "$api_root/klipy-api-key"
install -o cleo -g cleo -m 0644 "$stage/giphy_proxy.py" "$api_root/deltiecord_media_proxy.py"
install -o cleo -g cleo -m 0644 "$stage/candidates/app.candidate.py" "$api_root/app.py"
systemctl daemon-reload
systemctl enable --now deltiecord-web-push
systemctl restart contact-api
curl --fail --silent --show-error http://127.0.0.1:8141/api/push/config >/dev/null
curl --fail --silent --show-error 'http://127.0.0.1:5000/api/servers/klipy/search?mode=trending' >/dev/null
systemctl reload nginx
install -o cleo -g cleo -m 0644 "$stage/candidates/index.candidate.html" "$site_root/index.html"
install -o cleo -g cleo -m 0644 "$stage/candidates/cord.candidate.js" "$site_root/cord.js"
printf 'Cutover complete. Original Element service/files retained. Rollback backup: %s\n' "$backup"
