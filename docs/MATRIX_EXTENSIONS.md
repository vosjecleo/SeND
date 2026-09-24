# Deltiecord Matrix extensions

Deltiecord uses normal Matrix rooms, Spaces, events, encryption, media, and
MatrixRTC. Namespaced fields add presentation and lifecycle metadata; standard
membership/power levels remain authoritative. Other clients can ignore unknown
fields, but will not implement Deltiecord's role-propagation or timeout-restoration
behaviour. Current baseline: 0.9.34+107.

## Room presentation

- Type: room state event
- Event type: `net.deltiecord.room.presentation`
- State key: empty string

```json
{ "kind": "text" }
```

`kind` is `text`, `voice` or `forum`. Missing, unknown, or ignored state is presented as
a normal text room. A voice room remains an interoperable Matrix room and uses
standard MatrixRTC state for participation.

## Space channel categories and order

- Type: Space room state event
- Event type: `net.deltiecord.space.channels`
- State key: empty string

```json
{
  "version": 1,
  "categories": [
    { "id": "category-123", "name": "Games" },
    { "id": "category-456", "name": "Voice" }
  ],
  "rooms": {
    "!text:example.org": "category-123",
    "!voice:example.org": "category-456"
  }
}
```

Category array order is display order. `rooms` maps child room IDs to category
IDs; absent rooms are uncategorized. Actual room membership remains standard
`m.space.child` state. Deltiecord writes the standard `order` property on
`m.space.child` for room ordering, so clients that understand Matrix Space
ordering can retain a useful order without understanding categories.

The Space's standard `m.room.power_levels` event controls who may write this
layout through an `events["net.deltiecord.space.channels"]` entry. Deltiecord
initializes that entry to `100` (administrator) and exposes it in Space
settings. This permission and the layout state sync to every client; clients
that do not understand the namespaced layout can safely ignore it.

Collapsed categories are a per-account UI preference in
`net.deltiecord.settings`, not public room state.

## Synced Deltiecord settings

- Type: global user account data
- Event type: `net.deltiecord.settings`

The object currently contains UI preferences such as:

```json
{
  "theme_mode": "dark",
  "accent_color": 4285109721,
  "compactness": 0.5,
  "interface_scale": 1.0,
  "font_scale": 1.0,
  "timeline_chunk_size": 30,
  "timeline_chunk_cap": 3,
  "shortcut_bindings": { "openSettings": "control+comma" },
  "collapsed_channel_categories": {
    "!space:example.org": ["category-456"]
  }
}
```

It also stores notification/privacy toggles, panel sizes, selected font names,
read-receipt threshold, RTC processing choices, preferred device IDs, local
participant volumes, and other Deltiecord presentation preferences. Unknown
keys are preserved where possible. Other clients can ignore the entire event.
It contains no passwords, access tokens, recovery keys, media keys, or drafts.

Build 76 also stores these presentation and lifecycle values in the same
account-data object:

```json
{
  "presence_mode": "online",
  "temporary_room_mutes": {
    "!room:example.org": {
      "until": "2026-09-03T07:00:00.000Z",
      "restore_mode": "mentionsOnly"
    }
  },
  "desktop_idle_minutes": 10
}
```

`presence_mode` is `online`, `idle`, `doNotDisturb`, or `invisible`.
Temporary mute timestamps are UTC instants; Deltiecord restores the normal
Matrix push rule after expiry. Do Not Disturb suppresses this client's local
and push notifications. Other clients can ignore these hints.

## Personal saved messages

- Type: global user account data
- Event type: `net.deltiecord.bookmarks`

```json
{ "event_ids": ["$event1", "$event2"] }
```

This owner-only list supplements standard room `m.room.pinned_events`: pins are
shared room state, while bookmarks are personal. Unknown or unavailable event
IDs are retained and simply omitted from views until their room history is
available.

## Space pages

- Type: Space room state event
- Event type: `net.deltiecord.space.pages`
- State key: empty string

```json
{
  "welcome": "Welcome to the Space.",
  "rules": "Be kind.",
  "suggested_notifications": "mentionsOnly"
}
```

The two pages are plain text. The notification value is a suggestion, not a
forced client policy. Matrix clients that do not understand the state still
see a normal Space.

## Per-Space profile overrides

- Type: standard `m.room.member` state in the Space and its joined child rooms
- State key: the user's Matrix ID

```json
{
  "membership": "join",
  "displayname": "Delta",
  "avatar_url": "mxc://example.org/media",
  "net.deltiecord.pronouns": "they/them",
  "net.deltiecord.accent_color": 4285109721
}
```

Nickname and avatar use Matrix's ordinary room-specific member profile, so
other clients can display them. Pronouns and accent are optional namespaced
keys on the same membership state and are safe to ignore. Deltiecord mirrors
the chosen values to `net.deltiecord.space_profile_overrides` account data as
an owner-only migration/cache fallback, but public presentation comes from
room membership state.

## Active call device handoff

- Type: global user account data
- Event type: `net.deltiecord.active_call_device`

The value contains a Deltiecord device ID, Matrix room ID, and update timestamp.
When a second Deltiecord device joins the call, the older device leaves. The
entry expires after ten minutes and contains no WebRTC credentials or media
keys. MatrixRTC itself remains standard and other clients can ignore the hint.

## Moderation timeout restoration

- Type: room state event
- Event type: `net.deltiecord.room.timeouts`
- State key: empty string

```json
{
  "users": {
    "@user:example.org": {
      "until": "2026-09-02T14:30:00.000Z",
      "previous_power_level": 0
    }
  }
}
```

Matrix has no standard temporary-timeout primitive. Deltiecord enforces a
timeout with the standard room power-level event and uses this state only to
restore the previous level after expiry, including after a restart. Other
clients can ignore the state; the power-level restriction remains visible and
interoperable. Rooms that deny the moderator permission to write this custom
state can only restore automatically while the initiating client remains open.

## Standard interoperable events

Polls use Matrix poll events from MSC3381 through matrix-dart-sdk. Stickers are
sent as `m.sticker`; packs are read from the established FluffyChat-compatible
`im.ponies.user_emotes` account data and `im.ponies.room_emotes` room state.
Room pins use `m.room.pinned_events`, notification modes use Matrix push rules,
manual unread uses Matrix room account data, and moderation uses standard
membership and `m.room.power_levels` operations.

## Extensible profile fields

Deltiecord checks the homeserver's `m.profile_fields` capability before writing
extended fields. Unsupported fields remain unavailable rather than being
silently placed in account data.

| Field | Value | Fallback |
| --- | --- | --- |
| `m.tz` | IANA timezone identifier, for example `Europe/Amsterdam` | Omit timezone/local time |
| `net.deltiecord.bio` | Plain UTF-8 biography text | Omit About section |
| `net.deltiecord.pronouns` | Plain UTF-8 pronoun text | Omit pronoun label |
| `net.deltiecord.banner` | `mxc://` URI for the profile banner | Render colour/empty banner |
| `net.deltiecord.profile_color` | `#RRGGBB` primary colour | Use application accent |
| `net.deltiecord.profile_color_secondary` | `#RRGGBB` secondary gradient colour | Use primary colour |
| `net.deltiecord.voice_color` | `#RRGGBB` optional RTC tile colour | Derive a representative colour from the avatar |
| `net.deltiecord.voice_background` | `mxc://` URI for an independently cropped RTC tile background | Use the explicit or avatar-derived colour |

Display name and avatar use standard Matrix profile fields. Presence and the
short status message use standard Matrix presence APIs. A homeserver or client
that ignores the custom fields still sees a normal Matrix profile. The ordinary
profile banner is deliberately not reused as an RTC background: each image has
a different crop and privacy/presentation purpose.

## Threads and forum posts (106)

Replies use standard `m.thread` relations and fallback reply metadata. A forum
is an ordinary room with `kind: "forum"`; thread roots contain readable message
bodies (or image attachments) plus optional `net.deltiecord.forum.post` content:

```json
{"version": 1, "title": "A discussion", "tags": ["help"]}
```

Titles allow 1–120 graphemes; at most five unique tags allow 24 graphemes each.
Invalid metadata falls back to normal message rendering. Existing edits retain
forum metadata when replacement content does not provide it. The thread index
discovers older roots; unsupported homeservers fall back to ordinary history.
Threads share room membership/access. Following is an account-synced list under
`followed_threads` in `net.deltiecord.settings`, not an independent push rule.

## Named roles and Administration (106)

`net.deltiecord.space.roles` is Space state with an empty state key:

```json
{
  "version": 1,
  "roles": [{"id": "helpers", "name": "Helpers", "power_level": 50, "color": 4285109721}],
  "members": {"@user:example.org": ["helpers"]}
}
```

Stable IDs survive renaming/reordering. Multiple assigned roles contribute their
maximum power level; the first ordered role with a colour supplies name colour.
Role labels are server-profile presentation, not global identity changes.

Saving metadata and applying member powers are separate confirmed actions.
Standard `m.room.power_levels` remains the authority. Its
`net.deltiecord.role_power` map records each affected user's manual `baseline`,
last `applied` value and contributing `spaces`, preserving explicit overrides
and shared-child-room contributions. Authority checks and partial failures are
reported rather than silently replacing every child's permissions.

Administration Rules edits standard power-level defaults, action thresholds,
event thresholds and `notifications.room`. Encrypted inner message types cannot
be independently enforced by the homeserver; upload/account/alias policy is not
turned into a client-side permission system.

## Personal room event visibility (106)

`room_event_visibility` in `net.deltiecord.settings` contains `defaults` and
per-room `rooms` maps with boolean keys `avatar`, `name`, `membership`, `profile`
and `room`. Missing room values inherit defaults; missing defaults show events.
These are display filters, not deletion or room policy. Security/encryption and
moderation events are not hidden by cosmetic filters.

## Shared Space/room display and access policy (107)

State event `net.deltiecord.space.policy`, empty state key, may be stored on a
Space or a child room:

```json
{
  "version": 1,
  "default_channel_access": "restricted",
  "event_visibility": {"avatar": false, "name": false}
}
```

Visibility accepts the five cosmetic keys above. A room's explicit boolean wins
over its parent Space, then personal settings supply the fallback. Missing flags
inherit; protected security/moderation events remain visible. This is a shared
Deltiecord display policy, not event deletion or enforcement on other clients.

`default_channel_access` on a Space controls newly created channels: `invite`
(the fallback), `restricted` (Space members may join), or `public`. Actual access
uses standard `m.room.join_rules`; history uses `m.room.history_visibility` and
directory listing uses the standard directory API. Saving a default does not
modify existing channels; bulk updates require a separate confirmation. Space
membership does not automatically join every child room.

Pronoun entries are limited to 16 graphemes on write and old longer entries are
truncated for display. No SQL migration is needed for these additions.
