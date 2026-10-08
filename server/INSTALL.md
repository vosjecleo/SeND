# Run your own SeND server

The guided installer creates a new Matrix server and the services SeND uses.
It is for a **fresh, dedicated Linux host**, not an upgrade or migration tool.
It refuses to overwrite an existing installation directory. Nothing is installed
on Deltie by running the generator's tests.

## Before starting

Install Python 3.11 or later, Docker Engine and Docker Compose v2 using
[Docker's installation instructions](https://docs.docker.com/engine/install/).
Use a host with a public IPv4 address. NAT, shared reverse proxies, IPv6-only hosts
and existing Matrix servers need an operator-reviewed configuration instead.

Choose the Matrix server name carefully: `example.org` gives users addresses
such as `@alice:example.org`. It cannot be changed after accounts are created.
The installer needs exclusive control of that hostname's web service and five
more names: `matrix`, `chat`, `rtc`, `turn` and `push` under your domain. Point
their DNS records directly to the host, not through an HTTP CDN. Remove broken
AAAA records. The installer checks IPv4 DNS before starting services.

Open these ports in both the host and provider firewalls:

| Protocol | Ports | Purpose |
| --- | --- | --- |
| TCP | 80, 443 | HTTPS, certificates, Matrix and call signalling |
| TCP and UDP | 3478 | TURN |
| TCP | 7881 | LiveKit fallback |
| UDP | 7882 | LiveKit media |
| UDP | 49160–49260 | TURN relay media |

The script does not change firewall rules. Docker's published ports may bypass
some host firewall frontends. Review your provider firewall as well.
TURN-over-TLS on port 443 is not included; calls on networks allowing only HTTPS
may need a separate TURN IP, certificate and TLS listener.

Have these ready:

- A contact email for certificates and Web Push.
- A dedicated Telegram bot token from `@BotFather` for public pack imports.
- A KLIPY API key for GIF search. Follow the provider's terms and attribution rules.
- Optionally, an existing OIDC provider's issuer, client ID and secret. The
  default claim mapping expects `preferred_username` and `name`; review it for
  your provider. Register the callback printed by the wizard.
- Optionally, SMTP credentials for email verification and password resets.
  The wizard uses STARTTLS on port 587 and the contact email as sender.
- A SeND web release archive and its SHA-256 from the trusted release manifest.

Blank Telegram/KLIPY credentials leave those integrations unavailable. They do
not disable Matrix messaging. FFmpeg, Cairo and the pinned TGS conversion tools
are installed inside the media helper image, not on the host.

## Install

From a reviewed checkout of SeND:

```sh
sudo python3 server/install.py --directory /opt/send
```

The wizard writes private files first, then asks before building or starting
containers. Declining startup lets you inspect `compose.yaml`, `homeserver.yaml`,
`Caddyfile` and the other generated files. Do not print or share them: several
contain passwords. The directory is mode 0700 and files containing credentials
are mode 0600. Keep it outside a Git checkout; its generated `.gitignore` also
excludes everything. Docker administrators can read container credentials.

The stack includes Synapse/PostgreSQL, Caddy HTTPS, coturn, LiveKit and its Matrix
authorization service, ntfy, the media helper, and the Web Push gateway. Only
the edge proxy and RTC ports are published. Registration is closed; the wizard
offers Synapse's interactive command to create the first administrator. Later:

```sh
cd /opt/send
sudo docker compose exec synapse register_new_matrix_user \
  -c /config/homeserver.yaml http://localhost:8008
```

If you stop after generating files, or startup fails, keep the directory and
inspect the error. After correcting DNS, ports or configuration, finish from
that directory rather than rerunning the wizard:

```sh
cd /opt/send
sudo docker compose config --quiet
sudo docker compose build
sudo docker compose run --rm --no-deps caddy caddy validate --config /etc/caddy/Caddyfile
sudo docker compose up -d --wait --wait-timeout 180
```

If a service still fails, use `docker compose ps` and that service's logs. Share
only redacted logs, never `docker compose config` output or the private files.

Native Android can use SeND's built-in notification service without ntfy. For
UnifiedPush, configure the ntfy Android distributor to use `https://push.example.org`.
The generated ntfy service allows public, unguessable topics and rate-limits
requests. It is for encrypted Matrix push traffic, not plaintext private messages.
Review ntfy's access-control and retention settings before opening a public service.

Web Push stores subscriptions and its stable VAPID key in `push-data`. It only
accepts OpenID proofs from the configured Matrix server. It never receives
Matrix access tokens or room keys. Message previews, when enabled, are decrypted
on the receiving device. iOS requires a Home Screen installation and permission.

Last.fm and Steam are client integrations, not homeserver services. Official
SeND builds retain their existing provider configuration. For custom Last.fm
builds, register your own application, obtain the necessary provider approval,
and use the build credential mechanism in [BUILDING](../BUILDING.md). Do not
reuse SeND's private credentials. A client-embedded API secret is extractable.

## Your own endpoints

The PWA already uses same-origin GIF, Telegram and Web Push routes. Official
native builds still use Deltie's public GIF/Telegram services; hosting a Matrix
server does not silently redirect native clients to your helpers.

To use your services for native builds and web link previews, build with the
generated, non-secret `client-defines.json`. On your build machine:

```sh
bash packaging/build-web.sh --dart-define-from-file=/path/to/client-defines.json
```

Pass the same Flutter option to your native build. Stock PWA archives continue
to use Deltie for the allowlisted web-preview fallback. They are usable, but not
fully independent of Deltie. The installer does not rewrite compiled JavaScript
or build Flutter on the production server. An OIDC identity provider, SMTP
account, federation policy and provider approvals are not created automatically.

## Check before inviting users

```sh
cd /opt/send
sudo docker compose ps
curl --fail https://matrix.example.org/_matrix/client/versions
curl --fail https://example.org/.well-known/matrix/client
curl --fail https://example.org/.well-known/matrix/server
curl --fail https://chat.example.org/api/push/config
curl --fail https://chat.example.org/version.json
curl -I https://chat.example.org/
```

Confirm HTTPS and browser `crossOriginIsolated`, then test with two accounts:
encrypted messages and recovery, files/video, animated Telegram packs, GIF search,
calls across two different networks, screen sharing, and federation. Test Web Push
with the PWA closed on a real iPhone; desktop emulation does not establish this.
Test Android notifications with the selected service. Generic Matrix URL previews
are disabled in Synapse; SeND's allowlisted bridge and client preview policy remain
available. Review SSRF protections before enabling Synapse URL previews.

The configuration generator and helper tests are automated. A fresh-host live
installation and end-to-end calling/push still need operator testing; the installer
does not certify them merely because containers start.

## Updates, backups and recovery

Never rerun the wizard over an existing server or change its server name. Keep the
generated secrets, signing key, database, media and VAPID key. Do not use
`docker compose down -v`: it deletes persistent volumes.

Back up PostgreSQL with `pg_dump` and retain the matching media store, signing key,
private configuration and push state. Use encrypted backups and test restoration
on an isolated host. Keep database backups consistent with a supported PostgreSQL
version; copying a running database volume is not a reliable backup.

Review upstream release notes before changing pinned image versions, then run
`docker compose pull` and `docker compose up -d --wait`. Rebuild helpers after
copying reviewed sources, including **hosting_config.py**, into `helpers/`.
Back up before database migrations; changing an image tag back is not always a
valid database rollback. The wizard never rotates secrets during updates.

For PWA updates, verify the archive against its trusted SHA-256 manifest, then:

```sh
sudo python3 /opt/send/deploy-web.py /path/to/SeND-VERSION+BUILD-web.tar.gz \
  /opt/send/web VERSION+BUILD
```

The deployer validates archive contents and atomically switches `web/current`.
Retained release directories allow rollback by selecting the previous symlink
target. Keep the web hostname stable to preserve browser sessions and push grants.

Upstream references: [Synapse](https://element-hq.github.io/synapse/latest/setup/installation.html),
[LiveKit ports](https://docs.livekit.io/transport/self-hosting/ports-firewall/),
[MatrixRTC authorization](https://github.com/element-hq/lk-jwt-service).
