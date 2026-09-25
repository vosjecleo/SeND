# SeND 0.9.35+108 — release notes

SeND is a recursive acronym: **SeND is Not Discord**. The GitHub repository is
now `vosjecleo/SeND`; the local `github` remote follows that name. This document
records implementation and validation; CI/deployment results are reported separately.

## Compatibility boundaries

Visible branding, About text, login/onboarding, notifications, window titles,
Android label, PWA manifest/title, desktop launchers, installer UI and future
release filenames use SeND. Internal Dart identifiers and source filenames are
not renamed just for spelling: that would add churn without changing the UI.

Keep these stable deliberately:

- Android application ID, signing identity, deep links and notification IDs.
- Matrix SDK client name (`Deltiecord`), database names, settings keys, custom
  `net.deltiecord.*` events/profile fields and service endpoint paths.
- Native executable/package IDs and data directories; Linux still supports the
  `deltiecord` command/package ID; new packages also provide a `SeND` command.
  Windows keeps its Inno AppId so upgrades reuse
  existing installation directories instead of creating a second installation.
- Windows `CompanyName` and `ProductName` resource fields: both path_provider
  and flutter_secure_storage use these to locate existing secrets/databases.
  Renaming them without a coordinated storage migration would sign users out.
- Browser origin, manifest ID, IndexedDB and browser-private storage keys.

## Update downloads

The manifest parser accepts old `deltiecord-` and new `SeND-` artifact filenames.
It only selects artifacts matching the advertised version/build and selected
release channel, with bounded filenames, size and SHA-256 metadata. URLs are
constructed on `https://deltie.net/SeND/`, never trusted from arbitrary JSON URLs.

Android chooses the running ABI. Linux uses AppImage environment/package markers,
then bounded package-ownership queries for pre-marker installations. It does not
guess from the host distro. Windows distinguishes installed Inno builds from
portable ZIPs. Unknown local builds use the download chooser.

Windows installed builds additionally offer **Download and install**. This is an
explicit interactive upgrade, not an unattended updater: download to a unique
temporary directory, verify size/SHA-256, then start Inno with the existing install
directory. No shell, forced process kill, silent elevation or reboot. Failure
does not run the installer; the manual download remains available. Transfer
checksums from HTTPS are not Authenticode/publisher-signature verification.
Actual installer replacement/Restart Manager behaviour still needs Windows testing.

Inno references: [command-line options](https://jrsoftware.org/ishelp/topic_setupcmdline.htm),
[previous install directory](https://jrsoftware.org/ishelp/topic_setup_usepreviousappdir.htm).

## Website migration applied

`/srv/storage/www/deltie/SeND` is a symlink to the existing `cord` download store.
The new page and homepage descriptions are live, and status/contact navigation
uses SeND. Published binaries and `releases.json` were not modified.

The old `/cord` HTML page redirects in the browser via same-origin external JS;
canonical metadata points at `/SeND/`. This is not an nginx HTTP redirect.
Legacy `/cord/releases.json` deliberately stays HTTP 200: old clients disable
redirects when checking for updates. Old artifact links also stay usable.
No DNS, certificate, reverse-proxy, Matrix or PWA runtime configuration changed.

Backups/staging on deltie: `/home/cleo/send-site-jqRjUu5R/` (original homepage,
download page, contact and status pages). Website sources live in `server/website`.

## Last.fm credentials

Owner reports rotated keys; both existing `/home/cleo/lastfm-*.key` files retain
0600 permissions and were updated September 25. The local preview helper reads
them afresh per build without printing values. Previously compiled apps still
contain the previous credentials. Never commit keys or generated define files.
The local credential-enabled preview does not imply CI credentials are configured;
The owner confirmed both rotated CI secrets are configured before this release.
CI now reads `LASTFM_API_KEY` and `LASTFM_API_SECRET` repository secrets through
`packaging/flutter-with-credentials.py`, with a private temporary define file.
Main-branch builds fail rather than silently distributing an unconfigured login.
Builds also reject duplicated key/secret values and verify the pair with a signed
Last.fm request before compiling. The first unpublished build batch was withdrawn
after incorrectly duplicated CI credentials were reported; all release artifacts
are rebuilt from the corrected, guarded commit, not reused from that batch.
The rotated local pair passes Last.fm's signed application-authentication check.
Application credentials are necessarily present in a distributed Last.fm client;
these files must never contain user tokens or passwords.

## Pack editing and animations

The separate pack editor supports adding/removing items, individual emoji alias
changes, selection, bulk alpha crop/resize with preview, output size/filter
choices, and undo for item operations. Metadata-only changes do not upload media.
Stale snapshots and lost edit permission are checked before and after uploads.
Matrix state/account data has no atomic compare-and-swap; concurrent writes in
the final request window still use its standard last-write-wins behaviour.

Animated edits keep all frames and timings, use the union of visible alpha bounds
across frames, and encode a transparent GIF palette explicitly. This can reduce
colours and alpha precision compared with WebP; the preview shows the result.
Untouched valid assets retain exact bytes and original URLs. Work is bounded to
240 frames/24 Mi decoded pixels for transformations and normal upload limits.
Telegram's existing bounded animated conversion service remains in use; there
is no general-purpose conversion endpoint.

## iOS Web Push

See [ios-push-checklist.md](ios-push-checklist.md). The public push config endpoint
responds, but this host cannot verify receipt on a physical iPhone. A concrete
foreground-lease race could previously ACK and permanently lose a message push.
Additionally, the client used a non-standard `/api/push/_matrix/...` pusher URL;
[Synapse requires exactly `/_matrix/push/v1/notify`](https://github.com/element-hq/synapse/blob/develop/synapse/push/httppusher.py).
That registration blocker is corrected, with one exact nginx route staged.

The gateway now ACKs only after durable SQLite queuing, coalesces events per room,
and sends after the foreground lease expires/is released. Reading a room cancels
its pending alert; a zero-unread badge update cancels pending alerts for that
device. The browser clears the lease on pagehide as well as visibilitychange.
An initial retry-response proposal was rejected: Synapse's exponential backoff
could delay delivery for up to an hour after a long foreground session.
The final queue has a one-hour TTL, 256-room/device and 20,000-entry global bounds,
and a single background dispatcher in the existing one-worker gateway service.
Provider failures retry boundedly, invalid subscriptions are removed, and only
room/event IDs and existing subscription capabilities are stored. A read/open
race with an already in-flight push can still produce a visible notification;
Safari does not permit silently consuming a delivered push.

Picker previews, inline custom emoji and timeline media use the existing
lifecycle-aware renderer, including animated WebP detection when MIME metadata
is absent. Autoplay/reduced-motion settings remain respected.

The new explicit test endpoint requires the existing opaque registration
capability and is limited to two tests per minute. It bypasses foreground leases
only for user-requested tests. Every delivered push displays a notification,
as Safari requires; payloads still contain event IDs rather than decrypted text.
Diagnostics display only permission/installation/subscription booleans, not
push URLs, Matrix tokens or registration capabilities.

Root-owned gateway update staged on deltie in `/home/cleo/send-push-108/`; run
`sudo bash /home/cleo/send-push-108/install-web-push-update.sh`. This updates the
existing worker, enables its queue dispatcher in its systemd unit, and adds only
the exact standard push route to the inspected chat nginx snippet. It refuses
to overwrite files changed since staging, keeps rollback copies, checks nginx
syntax and service health, and leaves DNS, certificates and other hosts alone.
The queue table is added to the existing private push database automatically.

For the activity/media scope and outstanding platform limitations, see
[activity-local-preview.md](activity-local-preview.md).

## Validation

- Flutter analysis clean; 421 tests passed, two environment-dependent skips.
  Ten targeted editor/animation tests also passed after final narrow-keyboard and
  interpolation fixes. Browser Web Push suite: seven tests pass.
- Server suite: 34 tests pass in an isolated environment with the pinned web-push
  dependencies (the host Python alone did not have Flask). Focused updater/version
  tests also pass after the final dialog and download-timeout hardening.
- New regressions cover ABI/package matching, old/new artifact names, stable
  channel isolation, invalid metadata rejection and persistence-identity guards.
- Live Chromium mobile-viewport check: `/cord/` redirects to `/SeND/`, nine
  existing native downloads render, no error banner or horizontal overflow.
- `/SeND/` and both old/new release manifest URLs return HTTP 200. Manifest is
  still the published 0.9.34+107, not an invented/unbuilt 108 release.
- Packaging shell syntax checks and JavaScript syntax check pass. Windows
  installer handoff/replacement still requires Windows CI/manual validation.
- Four credential-guard tests pass, including duplicate values, invalid signed
  authentication and network failures without exposing secret response data.
