# SeND service helpers

Current client baseline: 0.9.35+110. See [web hosting](../docs/web-deployment.md)
and [hardening gates](../docs/RELEASE_READINESS.md).

`giphy_proxy.py` retains its historical filename but serves **KLIPY** search and
trending for current clients, alongside legacy GIPHY routes. Store the KLIPY key
in `/etc/deltiecord/klipy-api-key` (or `KLIPY_API_KEY_FILE`) with mode `0600` and
service-user access. Keep legacy GIPHY credentials separate if serving old
clients. Run on loopback and expose only documented routes through HTTPS.
Never log upstream KLIPY URLs: the credential is carried in their path.

Set `TRUSTED_PROXY_CIDRS` to the explicit reverse-proxy networks allowed to
supply `X-Real-IP`/`X-Forwarded-For`; the default trusts loopback only. Direct
clients cannot spoof those headers. `MAX_RATE_CLIENTS` bounds rate-limit state
and `MAX_CONCURRENT_REQUESTS` bounds upstream worker concurrency. Deploy one
process per configured capacity or put a shared limiter in front of multiple
processes; the in-process limits are intentionally not distributed.

The native client defaults to
`https://deltie.net/api/servers/klipy/search`. Alternative deployments can set
`GIF_PROXY_URL` at build time; this value is an ordinary public URL, not a
secret.

The same process optionally exposes public Telegram sticker-set imports at
`/api/servers/telegram/stickers`. Put a dedicated Telegram bot token in
`/etc/deltiecord/telegram-bot-token` with mode `0600`, or set
`TELEGRAM_BOT_TOKEN_FILE` to another private file. Clients submit only a
validated public sticker-set short name; the proxy resolves Bot API file IDs
and never returns its bot token or Telegram file URLs. Static PNG/WebP media is
bounded to 1 MiB per item, sets to 150 entries, upstream concurrency to the
shared request semaphore, and metadata caching to 64 sets for five minutes.
Animated TGS and WebM items are converted to animated WebP when the optional
conversion tools are installed. WebM uses FFmpeg; TGS uses the pinned packages
in `requirements-conversion.txt` and `lottie_convert.py`. By default the proxy
looks beside its Python interpreter; set `LOTTIE_CONVERT_BIN` when installing
the converter into a separate environment.
The endpoint never accepts uploaded media or arbitrary URLs: it resolves a
validated pack name and item index through Telegram's Bot API. Conversion is
limited to 128px emoji or 256px stickers, two concurrent jobs, fixed frame and
duration bounds, subprocess resource limits, a 64 MiB in-memory LRU cache, and
separate per-client/global rate limits. These defaults can be tightened with
`MAX_CONCURRENT_CONVERSIONS`, `TELEGRAM_CONVERT_RATE_LIMIT`, and
`TELEGRAM_GLOBAL_CONVERT_RATE_LIMIT`.

`TELEGRAM_RATE_LIMIT` defaults to 240 requests per client per minute so four
bounded client download workers can import a full 150-item set. Place a shared
limiter in front when running multiple proxy processes; like the GIPHY limiter,
this process-local limit is intentionally not distributed.
## Web preview bridge (introduced in 105)

`web_preview.py` extends the existing media service at
`/api/servers/preview`; `giphy_proxy.Handler.do_GET` dispatches that endpoint.
If embedding this handler in another service, also forward that exact path to
it and install `web_preview.py` alongside the media module. Deltie's existing
`/api/servers` reverse-proxy route is sufficient; no new listener or nginx
change is required. The PWA calls the HTTPS deltie.net endpoint, which allows
only the chat.deltie.net browser origin and sends CORP headers for isolated PWA
media playback. No Matrix credentials are sent to this service.

The bridge accepts only HTTPS URLs on its explicit provider allowlist, pins
connections to public DNS answers, validates each redirect, sends no upstream
credentials, and limits concurrency, rate, duration, MIME types and sizes.
Documents are limited to 1 MiB, images to 5 MiB, and video range responses to
8 MiB (512 MiB maximum declared resource size). HTML is sandboxed with a
no-script CSP; SVG and generic files are not served. This does not add media
conversion, arbitrary-site proxying, or support for every provider's player.

## Build 106 authentication callback

`chat-nginx.conf` contains an exact `/auth.html` rule with no access logging,
no-store caching, isolation/security headers and no application fallback. Apply
that narrow rule before enabling hosted browser SSO. It is not an identity
provider deployment and does not change Matrix, RTC, DNS or certificates.
The 106 PWA was deployed, but this privileged rule was left for the operator;
see [deployment status](../docs/web-deployment.md).
