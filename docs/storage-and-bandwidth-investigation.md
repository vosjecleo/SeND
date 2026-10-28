# Storage and bandwidth

Local investigation, 2026-10-28. These changes are not released or deployed.

## Local changes

- Search scope applies to bulk downloads and ongoing indexing: DMs; DMs and
  group chats; or DMs, group chats and server history. Existing installations
  retain the all-chats setting until the user changes it.
- Changing scope requires confirmation. It removes excluded local search
  entries and resets download progress, not messages or uploaded files.
- Profile avatars and banners open in a zoomable fullscreen viewer. Originals
  load on demand. Profile editors keep their crop gestures.
- Profile still previews and banner originals now use the bounded media pool.
  Still previews use separate keys so they cannot replace animated originals.
- The shared URL-preview cache now has a 16 MiB encoded-image budget as well as
  its entry limit. Active timeline widgets can retain their displayed images
  independently; this is not a total process-memory cap.
- Visible profile metadata uses 30-second checks for open profiles, the first
  five visible DMs and recent active-chat senders. Visible DMs ranked 6–10 use
  two minutes. Other watched profiles are checked once per session. Space icons
  use Matrix's synced room state, and offscreen room avatars are not eagerly
  downloaded. A supported homeserver batches up to 32 profile lookups; other
  servers use bounded standard Matrix lookups.
- Pending images have crop/move and quality controls. Static images can use
  original, 2048-pixel or 1280-pixel quality targets. Animated images are not
  flattened. Video presets select 12 MiB or 24 MiB limits, or original quality;
  browser videos remain unchanged. Defaults live in Local storage.

## Search size

The earlier synthetic desktop SQLite tests measured about 58.1 MiB for 100,000
15-character messages and 127.2 MiB for 100,000 200-character messages. IDs,
timestamps, secondary indexes and full-text indexing account for much of this.
These figures exclude the Matrix database and media. Android encryption and
browser storage can change the result.

A separate experiment with 100,000 15-character messages reduced the database
from 58.12 MiB to 43.61 MiB, about 25%, by using external-content FTS5 and
omitting its token-count table. The chronological search result fixture matched.
This was a disposable synthetic database, not a production migration. Edits,
redactions, fallback tokenizers and interrupted migrations still need testing
before changing the stored format.

Room/sender dictionaries and smaller secondary indexes could save more. They
require migration and query-plan tests. Replacing trigram search with word-only
indexing would change substring and language behavior, so it is not a drop-in
size optimization. Compressing the database file itself would not preserve
normal random-access SQLite updates.

## Cache and traffic audit

Confirmed in source:

- Avatar rows request original media to preserve animation. A small decoded
  image does not imply a small download. Changing this needs separate still
  and animated loading paths, including selected-room and hover behavior.
- The avatar pool allows 24 MiB in memory, 48 MiB on disk and 8 MiB per item.
- Profile media allows 48 cached profiles and 32 MiB of encoded media in memory.
- Attachment bytes allow 64 entries and 64 MiB in memory.
- GIF downloads allow 32 entries and 32 MiB in memory.
- URL previews expire after six hours, with at most 128 cached URLs. The local
  patch also caps cached encoded images at 16 MiB.
- Profile hydration previously fetched still previews and banner originals
  without the persistent media pool. The local patch adds bounded reuse.
- “Application data” currently measures the application-support directory,
  not every OS cache or temporary directory. It is not a complete device-storage
  breakdown. “Clear media cache” is not a complete purge of every disk cache.
- The SDK file cache is configured with a zero-byte admission limit. It should
  not be blamed for a large media cache without measuring actual files.
- SDK file storage currently points at the directory containing the Matrix
  database. Do not enable its age-based file cleanup there: that implementation
  walks ordinary files in that directory. Move media to a dedicated directory
  before enabling cleanup.
- Verified encrypted-video playback keeps temporary ciphertext. Integrity
  checking may require fetching the whole video before playback. Those bytes
  belong in transfer and temporary-cache accounting.

The reported 900 MiB and 2.77 GB are not attributed to specific sources yet.
A later Pixel 8 check of the earlier installed preview showed a 0.6 MiB search
index, 41.2 MiB application-support data and about 24 KiB transferred during a
30-second idle Home sample. Android's separate diskstats cache report was not
fresh enough to treat as a directory audit. These measurements are not from
build 133. Further performance profiling was deferred by the user. A useful next measurement
is directory-level cache accounting plus aggregate request bytes by endpoint
category, without logging tokens, URLs, room IDs or message contents. Compare
idle, scrolling, opening profiles and playing media separately.

Smaller thumbnails can reduce bandwidth. Deleting caches too aggressively can
increase it by forcing downloads again. Prefer byte-bounded LRU caches, expiry
for stale previews and on-demand originals over clearing everything on resume.

## Server storage implementation, not deployed

Settings now separates Local storage and Server storage. The latter shows
uploaded media usage, remaining allowance and a segmented category bar.
Pruning previews select up to 100 matching files, largest first. The default
media allowance is 12 GiB, with server-side per-account overrides.

The `send_storage.py` Synapse module derives the owner from Synapse's request
authentication. Clients never receive an admin token. Deletion previews issue
single-use, owner-bound tickets that expire after ten minutes. Ownership and
asset protection are checked again before deletion.

The read-only `server/storage_audit.py` script inventories one user's uploads
through the admin API and prints aggregate sizes. It defaults to a 12 GiB
allowance for reporting. It does not enforce quota, delete media or configure
Synapse. It requires an owner-only admin token file and allows HTTPS or local
loopback HTTP, without redirects. Synapse's inventory can include URL-preview
images attributed to the user, so this audit is not yet a billing counter for
user-initiated file uploads alone.

```sh
python3 server/storage_audit.py \
  --synapse http://127.0.0.1:8008 \
  --admin-token-file /etc/send/synapse-admin-token \
  --user '@alice:example.org'
```

### Accounting

- Count original uploads once per MXC ID. Track generated thumbnails, remote
  media caches and backups separately from the user's upload allowance.
- Use Images, Videos, GIFs, Audio and Other. Synapse cannot inspect encrypted
  attachments to recover these types. Older encrypted files start under Other.
- SeND writes `net.deltiecord.gif_source` into the message event. Encrypted
  events hide that field from the server. Optional storage labels contain
  media ID, media type and source category, not the message, room ID, filename
  or encryption key. A per-account device-local retry queue survives restarts.
- Distinguish uploaded Klipy GIF copies from external GIF references. Only
  uploaded bytes count toward upload quota. A normal GIF MIME type does not
  identify Klipy as its source.
- Categorization is off by default. The user can enable it in Privacy or Server
  storage, with an explanation of the metadata being shared. It labels new
  uploads and own attachments encountered in opened chats. Forwarded media
  owned by someone else is rejected without blocking other labels. Sticker
  references are not treated as new prunable uploads. Missing labels do not
  prevent accounting.
- Synapse does not provide a reliable per-user message-database byte total.
  Do not invent a Messages slice in the media-quota graph. Show message storage
  as separately managed unless an explicit server accounting model is added.

### Pruning and quota

Pruning has a count/size preview and age/type/source filters, followed by explicit
confirmation. Current avatars and protected assets are excluded. Unlabelled
historical uploads are counted but not bulk-pruned without knowing their purpose.
Deleting media can break attachments in everyone's history and cannot revoke
copies on other homeservers or devices. Messages are not deleted or redacted.
There is no automatic pruning.

A PostgreSQL admission trigger enforces the retained-upload allowance in the
same transaction as the media row. Per-owner advisory locks protect concurrent
uploads across workers. A Synapse preflight callback rejects ordinary over-quota
uploads before writing bytes. The version-pinned upload adapter cleans up failed
new uploads whose media row remains pending. Other Matrix clients use the same
server admission rules. Existing over-quota media is retained. Synapse's
`max_upload_size` limits individual files, and time-window upload limits are
not a retained-storage quota.

`install_storage.py` is read-only unless `--apply` or `--rollback` is supplied.
It validates the selected Compose stack and Synapse version, backs up configuration
privately, applies the additive schema and recreates only Synapse. Rollback restores
configuration and removes the admission trigger without deleting classification
records. Fresh-host setup can run the same optional storage step after Synapse's
initial database migrations.

Tests passed against isolated Synapse 1.159.0 and PostgreSQL 16: authentication,
inventory, quota refusal, owner labels, deletion tickets/replay protection,
recovered allowance and profile batching. Separate PostgreSQL tests covered
concurrent admission, pending uploads and quota reductions. The production
installer requires privileged operator checks. No production configuration or
media was changed.

Sources: [Synapse user media APIs](https://element-hq.github.io/synapse/latest/admin_api/user_admin_api.html),
[media callbacks](https://element-hq.github.io/synapse/latest/modules/media_repository_callbacks.html),
[media configuration](https://element-hq.github.io/synapse/latest/usage/configuration/config_documentation.html),
[SQLite FTS5](https://www.sqlite.org/fts5.html).
