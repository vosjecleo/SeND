# 0.9.34+106 implementation and validation tracker

Released on 2026-09-24 as **0.9.34+106 Latest** on GitHub and deltie.net.
All four CI targets passed. The verified Linux artifact was installed locally
and chat.deltie.net was switched to build 106. Release tag: `v0.9.34-b106`;
source commit: `b0ef233fa2106325b89fad3f683ed197f2cd388a`.
This closes feature scope; see [1.0 hardening gates](RELEASE_READINESS.md).

## Scope audit

- [x] Onboarding: bounded scroll content with navigation outside its viewport.
- [x] Shared profile layout across sidebar, popovers, full views, mobile and
  global/server editors. Bounded taller popovers with internal scrolling.
- [x] Live profile-card-backed banner/avatar crop masks, square avatar viewport,
  connected thought-bubble outline and 16-grapheme pronoun limits.
- [x] Fresh desktop composer document and pending styles after sending, addressing
  pasted style/background leakage instead of covering it with another colour.
- [x] Merge native/CSS safe areas and scale consistently, without blanket padding.
- [x] Synced personal room event filters and inherited defaults. Encryption and
  moderation/security notices remain visible; no event deletion.
- [x] Administration with separate Roles/Rules sections: stable role IDs, multiple
  assignments, ordered name colours, server-profile badges and maximum role power.
  Explicit propagation targets, authority checks and partial-failure reporting.
- [x] Rules cover message/encryption/sticker/reaction/poll events, membership and
  moderation, member defaults, permissions, room metadata/access/history/aliases,
  channel linking/reordering/categories, server packs, roles/pages, timeouts,
  voice membership/ringing and text/voice/forum presentation.
- [x] Standard Matrix threads: desktop side pane/mobile page, paginated replies,
  loaded participant counts, edits, reactions and attachments through the existing
  media pipeline. Disposable subscriptions, bounded relation-fetch concurrency,
  thread-specific receipts and notification navigation.
- [x] Main timeline collapses thread replies; a representative reply preserves
  access when a root is outside loaded history. No old root is injected into SDK
  pagination or sensitive scroll bookkeeping.
- [x] Forums: ordinary Matrix rooms, standard threaded replies, post titles/body/
  tags and optional image covers, loaded-post search/filtering, recent-activity/
  oldest sorting, unread indicators and synced Following list. Failed submissions
  retain text and cover selection.
  The server thread index includes active posts outside the loaded room window;
  older homeservers retain an ordinary-history fallback.
- [x] Login-method discovery, browser Matrix SSO and SDK OIDC/PKCE, SDK token
  persistence/refresh, validated callbacks and cancellation. Encryption-device
  verification/recovery remains separate from authenticating the account.

## Interoperability and deliberate boundaries

Roles use `net.deltiecord.space.roles`. Atomic member-power updates preserve
manual baselines and contributions from multiple Spaces in
`net.deltiecord.role_power` within the power-level event. Saving role metadata
and applying power are explicit separate steps: no silent administrator demotion
or overwriting every child-room override.

Existing `net.deltiecord.room.presentation` gains `forum`. Post metadata is
`net.deltiecord.forum.post` in an ordinary message/attachment, with a readable
fallback body; replies use `m.thread` and fallback relations. Following is a
synced organisational list, not independent thread push subscriptions. Room
notification settings still govern alerts.

Threads share their room's access. Private threads and independent server-enforced
thread locks require separate rooms/backend support and are not advertised.
Encrypted inner message types cannot be independently enforced by a homeserver.
Account creation, alias registration and upload policy remain server concerns.

No new SQL migration is required: existing SDK events/account data store the new
metadata. Old clients still receive ordinary messages/media.

## Authentication hosting

Native browser login uses a random-port loopback listener and random callback
path, not an embedded webview. Android's return link only foregrounds the app;
an exported activity never accepts login credentials. Web opens a window from
the user gesture and uses same-origin BroadcastChannel with destination/session/
state validation. No callback tokens are stored in localStorage.

`server/chat-nginx.conf` adds an exact `/auth.html` location disabling callback
query logging/caching and preserving security headers. **Not deployed.** Review
and apply that narrow rule before enabling browser SSO on the hosted app; do not
replace unrelated TLS/Matrix/RTC configuration. This patch enables no identity
provider on deltie.net. Its current password-only configuration cannot exercise
an actual SSO/OIDC sign-in.

## Validation still required before stable/1.0

- Real Windows clipboard paste/send in light/dark modes.
- iOS PWA/rounded-screen safe areas and keyboard cycles; real identity-provider
  redirects, including standalone PWA/browser storage partition behaviour.
- Android loopback return while the browser is foregrounded and cancellation/process
  interruption. Native package/platform compilation passed on CI.
- Real homeserver SSO/OIDC, refresh after relaunch, cancellation during exchange
  and subsequent device verification/encryption recovery.
- Two-client encrypted discussions/forums: older pages, reactions/edits, limited-
  sync resume, receipts/notification taps and legacy-client fallback rendering.
- Real owner/moderator/non-admin permission propagation, shared-Space child rooms
  and partial failures.
- Global/server profile crop/pan/zoom visual review with EXIF-oriented photos.

Automated coverage includes onboarding at 360x640/130% text, narrow profile
layouts, crop geometry/output pixels, Unicode pronouns, clean composer styles,
safe-area scaling, event-filter inheritance, role authority/power preservation,
partial propagation, thread cancellation/disposal, forum retry drafts, discovered
login methods and callback rejection.

Final local regression checks (2026-09-24):

- Full Flutter test suite: 366 passed, one existing skip.
- Flutter static analysis: no issues found.
- Callback JavaScript syntax and `git diff --check`: clean.
- All four platform workflows and publication passed; ten artifact checksums were
  verified before publication to Deltie. PWA `version.json` reports 0.9.34 / 106.
- The browser autofill regression passed after allowing semantic-layout geometry
  to settle before its mode-switch click. Failure screenshots are retained by CI.
- The `/auth.html` nginx rule remains an operator step, not a completed deployment.
