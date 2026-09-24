# Web/PWA deployment

## Current deployment: 0.9.34+107 — 2026-09-25

Build 107 passed Web/PWA CI (including browser autofill/mode-switch regression)
and was deployed atomically to `chat.deltie.net`. Public `version.json` reports
version `0.9.34`, build `107`. All four platform
artifacts are published as Latest. See [1.0 readiness](RELEASE_READINESS.md) for
the distinction between feature-scope completion and real-device validation.

**Pending operator action before browser SSO:** the new exact `/auth.html` nginx
rule prevents callback codes/tokens entering access logs or caches. The PWA
files are deployed, but this privileged configuration change was not applied.
On Deltie, the inspected, narrowly scoped candidate and backup/rollback script
are staged under `/home/cleo/deltiecord-106-server`:

```sh
ssh -t deltie 'sudo bash /home/cleo/deltiecord-106-server/apply-auth-nginx.sh'
```

The script refuses a changed live snippet, backs it up, validates nginx, and
reloads only after validation. Other hosts should adapt only the callback rule
from `server/chat-nginx.conf` after reviewing their live configuration. Do not
overwrite unrelated Matrix, RTC, TLS or proxy configuration. This does not enable
an identity provider on the password-only Deltie homeserver. Real-provider and
iOS standalone-PWA callback behaviour still need testing.

## Routine updates

For subsequent published releases, `/home/cleo/update-deltiecord.sh` on deltie
can re-select the latest web artifact from the local downloads manifest. Run it
as `cleo`, without sudo. It validates the artifact name and SHA-256, takes an
update lock, and uses `packaging/deploy-web.py` for bounded extraction and an
atomic `current` symlink switch. It does not build, change release channels,
edit services, or restart nginx. Normal automated publication already performs
the web switch; this is also available for a manual retry.

Build 99 adds a separate browser artifact; it does not replace Matrix or run
Matrix encryption on the server. `bash packaging/build-web.sh` builds pinned
vodozemac Rust/WASM bindings, checks the committed Dart lockfile, builds Flutter
without remote renderer dependencies, and packages `dist/*-web.tar.gz`.

## Hosting prerequisites

### Historical build 99 cutover — 2026-09-23

The owner completed the approved cutover from Element to Deltiecord at
`chat.deltie.net`. Post-cutover checks confirm version 0.9.30 build 99, active
nginx/contact-api/Web Push services, the required isolation headers and WASM
MIME type, working public KLIPY search/trending routes, and a responding Web
Push configuration endpoint. The download site now includes the Web/PWA entry.
An isolated Chromium smoke test of the live site reached startup without
JavaScript errors, opened the SDK's IndexedDB database, and activated `/sw.js`.
These infrastructure checks do not establish end-to-end notification delivery
on a real iPhone; the real-device checklist below remains required.

Reported first-release issues are tracked in
[the build 99 follow-up notes](web-build-99-follow-up.md). No fixes for those
reports are included in this deployment verification.

A new host's deployment is **not complete** until it has all of these:

- HTTPS with a valid certificate, serving the complete archive at `/`.
- `Cross-Origin-Opener-Policy: same-origin` and
  `Cross-Origin-Embedder-Policy: require-corp` (required by the SDK's shared WASM
  memory). Check `crossOriginIsolated` in the browser, not just nginx syntax.
- Correct WASM/JavaScript MIME types. Do not cache `index.html`,
  `flutter_bootstrap.js`, `version.json`, `browser_bridge.js`, or `sw.js` across
  deployments. Do not rewrite `/api` or missing crypto files to `index.html`.
- A CSP permitting the local Flutter/WASM runtime, workers (including blob
  workers), HTTPS/WSS Matrix connections, media/blob images, and WebRTC. The
  marketing site's CSP/Permissions-Policy disables required app capabilities;
  do not change that site's global policy to accommodate this app.
  The pinned flutter_rust_bridge loader calls `new Function`, so this app's
  script policy currently needs `unsafe-eval` as well as WASM compilation.
  This reduces CSP's defence-in-depth against script injection; third-party
  scripts remain disallowed. Recheck removal when upgrading that dependency.
- Same-origin `/api/servers/klipy/search` and Telegram media proxy routes.
  The shared public media helper also permits read-only CORS from exactly
  `https://chat.deltie.net`, because the initial browser build retains the
  native Telegram endpoint on deltie.net. It does not allow credentials.
  Keep old GIPHY routes working for older native builds. KLIPY's credential
  remains in a mode-0600 service file, never an environment variable embedded
  in Flutter or browser assets.
- `/api/push/*` routed only to the new loopback Web Push gateway. Do not expose
  a debug server or change unrelated Matrix/RTC/proxy routes.

`packaging/deploy-web.py` validates archive paths, required assets and version,
extracts into an immutable version directory, and atomically switches a
`current` symlink. Rollback is selecting the previous release directory. The
release publisher transfers this script with the checksum-verified archive.

**Historical pre-cutover installation:** inspection found Element already serving
`chat.deltie.net`. The owner approved replacing Element there. Preserve its
files/configuration and browser data; do not clear
Element's IndexedDB. Inspect existing service-worker scope/caches during the
cutover. The SSH account currently also needs privileged assistance to update
nginx/certificates/services. No such server changes were made during inspection.

## Historical chat.deltie.net cutover (completed; do not rerun for updates)

The release stages the following files under `/home/cleo/deltiecord-99-server`
on `deltie`. The private KLIPY key is copied separately with mode 0600 and is
never committed or included in any client artifact. After release publishing:

```sh
ssh deltie
cd /home/cleo/deltiecord-99-server
diff -u /etc/nginx/sites-enabled/matrix candidates/matrix.candidate
diff -u /srv/storage/services/contact-api/app.py candidates/app.candidate.py
less chat-nginx.conf deltiecord-web-push.service apply-chat-cutover.sh
sudo bash ./apply-chat-cutover.sh
```

`diff` exit 1 is expected when showing changes. If Python venv support is absent,
install the Debian `python3-venv` package before running the script. Check that
`admin@deltie.net` is a monitored contact, or edit the service's contact setting.
The script checks hashes of the inspected live files and refuses stale
candidates; creates a private timestamped rollback directory; creates only the
dedicated push account/service; installs a stable VAPID key and fixed-version
gateway dependencies; tests nginx and the two loopback services before reload.
It preserves the old Element service on port 8089 and its data, and does not
touch DNS, certificates, Matrix or RTC blocks. It does not print secret values.

Check `https://chat.deltie.net/version.json` reports **0.9.30 / 99**, open the app
and confirm login, then perform the real-iOS checklist below. If an old Element
service worker remains in control, reload once after the new worker activates;
do not clear all site storage as that would remove existing Matrix keys.

Rollback: restore the `matrix`, `app.py`, and `deltiecord_media_proxy.py` files
from the printed backup to their original locations; run `sudo nginx -t`, then
reload nginx and restart contact-api. Disable `deltiecord-web-push` if reverting
the feature. Keep its private VAPID key/state for future re-enabling. Back up
that private state only with an explicitly encrypted backup policy.

## Web Push gateway

Use a dedicated unprivileged service account and a private state directory,
excluded from public/static hosting and unencrypted backups. Install
`server/requirements-web-push.txt` in its own virtual environment. Generate a
P-256 VAPID private key with a standard cryptographic tool, mode 0600, and keep
that key stable across deployments. Configure `WEB_PUSH_STATE`,
`WEB_PUSH_PRIVATE_KEY`, and `WEB_PUSH_CONTACT` (a monitored mailto address).

Run `web_push:app` from the `server` directory using gunicorn with **one worker,
four threads, a 45-second timeout, and a loopback bind**. The bounded in-memory
rate limiter assumes one worker. A multi-process deployment needs an external
shared rate limiter first. Retain normal nginx request/body/time limits; never
log request bodies or OpenID tokens. The gateway verifies short-lived OpenID
proofs against explicitly configured homeservers, limits subscriptions per
account and globally, and permits only known browser push hosts. Subscription
capabilities are stored in a mode-0600 SQLite file under a mode-0700 directory.

Foreground clients refresh a short visibility lease. Suppression is done before
sending a push because Safari requires every delivered push to display a
notification. If a visibility update is lost, the lease expires within a minute.
Payloads contain only room/event IDs; the worker displays generic text, never
decrypts messages, and contains no Matrix session credential. Expired endpoints
are removed on 404/410. Transient delivery failures return 503 for Matrix retry.

## Validation before publication

- Run formatting, analysis, full native Flutter tests and Python tests in the
  gateway virtual environment. Run JS syntax checks and the Web/PWA workflow.
- `python3 tool/serve_web.py` serves a local isolated build on port 8139 for
  browser smoke tests. Confirm SDK crypto startup, desktop/mobile layouts,
  single-tab exclusion, reload persistence, login/logout, encrypted send/receive,
  and media opening. Use a test account, not copied production credentials.
- On a real iPhone/iPad (16.4+), install from Safari onto the Home Screen, grant
  notifications with the in-app button, background/close it, send a test Matrix
  event, and verify display, click navigation, permission revocation and logout.
  Desktop Chromium emulation cannot verify actual iOS push delivery.
- Verify deployed `/version.json`, crypto assets and security headers, and
  check the live KLIPY and Web Push paths. Only then advertise the public app.

## Known browser boundaries

The SDK owns IndexedDB session/crypto persistence; small app documents use the
existing secure-storage plugin's WebCrypto implementation. Browsers can still
evict storage, and same-origin script compromise can access a browser session.
Keep a Matrix recovery key and avoid private browsing for durable sessions.

Native gallery enumeration is replaced by the browser picker. Video playback
uses a bounded (25 MiB) SDK-decrypted Blob URL because browser video elements
cannot use the native authenticated range proxy. Blobs are released when their
playback references are closed. Codec support and background call behaviour are
browser-dependent. General direct link previews remain subject to browser CORS;
homeserver previews are preferred. Web Push initially accepts only deltie.net
OpenID issuers; add other trusted issuers deliberately, not via arbitrary URL
discovery.
