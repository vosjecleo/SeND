# SeND architecture

Documentation baseline: 0.9.37+118. See [release readiness](RELEASE_READINESS.md)
for the distinction between implemented features and validated behaviour.

## Data flow and boundaries

### Composition and audio (build 117)

Desktop and mobile use plain text fields, not WYSIWYG editing. Desktop retains
the Quill document/controller solely for existing draft persistence and stable
emoji/mention offsets; no `QuillEditor` is mounted and imported rich styles are
not serialized. Build 118 parses only inline italic/bold/underline/strike/spoiler
markup on send; block Markdown remains literal and line breaks stay explicit. Timeline HTML
rendering remains independent and continues to display received formatting.

`AudioAttachmentPlayer` is shared across layouts. Matrix mapping carries voice
markers, duration and bounded waveform samples into `ChatAttachment`. Playback
is lazy: no eager decryption/download or media player allocation for every idle
audio row. A duration missing from the event displays as unknown until playback
metadata arrives. Actual position streams update only the player row.

### Backend ownership

Flutter widgets depend on `ChatBackend` and the SDK-independent models in
`lib/models`. `MatrixBackend` implements that contract and is the only layer
that owns matrix-dart-sdk objects. A normal update flows as follows:

```text
Matrix sync or UI command
        |
        v
MatrixBackend and focused Matrix subsystems
        |
        v
immutable chat/profile/RTC model snapshots
        |
        v
desktop ChatShell or mobile MobileChatShell
```

This boundary keeps Matrix events, rooms, clients, timelines, encryption
objects, and WebRTC sessions out of widgets. Platform integrations follow the
same pattern through notification, window, temporary-file, and microphone-test
services.

## State ownership

- `MatrixBackend` owns the authenticated client, selected Space/room, bounded
  room snapshots, preferences, encryption state, and subsystem lifetimes.
- matrix-dart-sdk owns the persistent Matrix database, sync state, room state,
  encryption sessions, and active timeline objects.
- `ChatShell` and `MobileChatShell` own platform-appropriate ephemeral
  navigation and popup state. Feature widgets own
  only short-lived presentation state such as hover, selection, and editors.
- `DraftStore` owns private per-room composer drafts on the local filesystem.
  Drafts are never written to Matrix room state.
- `ScheduledMessageStore` owns the private local send-later queue. Due entries
  use the normal encrypted send path while connected; overdue entries retry on
  the next launch. The queue is not advertised as server-side scheduling.
- Account preferences are mirrored to `net.deltiecord.settings` account data.

## Session lifecycle

Initialization creates one Matrix client, restores its database/session, then
attaches sync, login, notification, and connection listeners. Login starts
encryption/recovery refresh and metadata hydration. Logout and disposal cancel
listeners and timelines, stop RTC, clear local media capabilities, remove
secret-bearing proxy entries, and dispose the Matrix client. Async room work is
guarded by a monotonically increasing timeline generation so stale A to B to C
room loads cannot publish into the current room.

## Timeline lifecycle and windowing

Opening a text room obtains a timeline page, decrypts it, publishes usable text
immediately, and hydrates avatars, replies, and homeserver link previews
afterward. Four bounded room snapshots keep warm A to B to A switches useful
while a new SDK timeline is being acquired.

Timeline history and caches are bounded separately. Search, pin, reply and
notification navigation can reconstruct history around a target rather than
paginating from the present. Preserve stable Matrix event identities and avoid
changing scroll bookkeeping as a side effect of metadata or feature work.
The [scroll investigation](timeline-scroll-investigation-99.md) remains an
investigation record, not proof that every jitter cause has been eliminated.

## Media pipeline

Matrix media remains behind `ChatBackend`. Images and small files use bounded
downloads. Encrypted video is exposed to the native player through
`MediaRangeProxy`, a loopback-only HTTP range server with random capability
paths. Encrypted ciphertext must be fully downloaded and checked against its
declared SHA-256 before decryption/playback; seeking then reuses the verified
cache. This is not early unauthenticated streaming. Tokens, AES keys, and IVs remain in memory and are cleared on release,
expiry, logout, and shutdown. Decrypted files opened externally are written to
a private temporary directory and removed by age, not immediately while an
external application may still be reading them.

Link previews use the configured homeserver by default. A bounded URL-level
cache avoids duplicate preview requests. The optional direct fallback is off by
default and uses DNS/address validation plus pinned sockets so redirects and DNS
rebinding cannot target local services. GIF search uses the documented
SeND KLIPY proxy. Picker previews and selected media use bounded shared
fetches/caches; older GIPHY favourites remain supported.

## Mobile UI boundary

`lib/ui/mobile` contains the phone shell (Android and mobile web), navigation rail, timeline, details
panel, profile sheet, media views, and MatrixRTC presentation. Those widgets use
only `ChatBackend` and SDK-independent models. Navigation, timeline, and details
remain mounted as sliding layers so drawer gestures preserve room scroll state
and drafts. The desktop widget tree is selected independently and is not resized
into a phone layout.

## RTC ownership

`MatrixVoiceController` owns the single active MatrixRTC group call and every
associated WebRTC stream, track, timer, and subscription. It applies persisted
device and local-volume preferences, reconnects when selected devices vanish,
and releases capture/playback resources on leave or dispose. Persistent voice
channels remain ordinary Matrix rooms with MatrixRTC membership state. Their
text is available through Open chat in the desktop/mobile details panel.

Joining from another SeND device updates a short-lived owner hint in
account data. A previously connected SeND client then leaves its local
call; MatrixRTC media state and credentials never enter that hint.

## Interoperable collaboration features

Polls, room pins, push rules, manual unread state, moderation, invitations,
aliases, and power levels use Matrix protocol/MSC representations supported by
matrix-dart-sdk. Sticker packs consume the established
`im.ponies.*_emotes` formats and send standard `m.sticker` events.
SeND-only Space pages, personal bookmarks, profile overrides, presence
UI state, and call handoff hints are isolated in documented `net.deltiecord.*`
state or account data so other clients can ignore them safely.

## Caching and cleanup

Avatar, decrypted preview, reply, and link-preview caches are pruned with room
or timeline lifetimes. Flutter's decoded image cache is bounded at startup.

User profiles use a field-aware shared cache. Cached profile data can be displayed
while background refreshes run; media bytes are reused by URI across surfaces.
Presence comes through Matrix sync, while extensible profile metadata needs
separate refreshes. Profile editing and viewing use the shared profile-card layout
and crop masks rather than independent approximations of banner/avatar geometry.
Media players and playback sources are reference counted by message ID.
Temporary files, local proxy capabilities, timers, stream subscriptions,
editors, and WebRTC resources all have explicit shutdown paths.

## Threads, forums and administration (106)

`ThreadSession` is the SDK-independent discussion boundary. Matrix thread
sessions own their timeline/subscriptions, page relations, reuse message/media
sending and mapping, and dispose on close. Desktop shows a side pane; mobile
opens a discussion page. Thread-specific receipts and notification navigation
are separate from the main timeline's read frontier.

Forums combine ordinary room history with the server thread index. Post metadata
adds titles/tags to readable message bodies; replies remain standard threads.
Following and personal cosmetic-event filters use existing account preferences.

Administration stores ordered role metadata separately from permission updates.
Applying roles writes standard room power levels with preserved manual baselines
and per-Space contributions. There is no new database migration or parallel
permission engine. See [the extension contract](MATRIX_EXTENSIONS.md).

## Browser authentication (106)

Login-method discovery precedes Matrix SSO or SDK OIDC/PKCE. Native platforms
use an external browser and random loopback callback; web uses a same-origin
callback/BroadcastChannel. Destination/session/state checks, cancellation and
SDK persistence remain explicit. Login never substitutes for encryption-device
verification. See [networking](networking.md) and [hosting](web-deployment.md).

## Media preparation and calls (current)

`VideoPreparation` serializes native video preparation and owns the progress,
error/retry/original/cancel state. Android stages files through path_provider in
Context.cacheDir; the Media3 bridge validates canonical paths beneath that root.
Desktop encoding uses FFmpeg; web keeps original files. Matrix upload/encryption
still happens after preparation in the normal attachment send path.

DM calls keep a bounded call area above chat. Voice channels expose text through
Open chat in the details panel. Browser audio elements belong to the call, not
individual tiles, so navigating/fullscreening cannot duplicate or drop playback.
Mute gates outgoing microphone tracks (including clones); deafen gates remote
voice and screen-share audio. Visual speaking state follows live microphone
levels rather than stale SDK speaker membership. TURN credentials refresh before
expiry; floating controls expose actual peer/connection diagnostics.
