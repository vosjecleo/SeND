# From feature completeness to 1.0

## Milestone: 0.9.34+106

On 2026-09-24, SeND reached the end of its planned feature-expansion phase.
The intended product is now implemented in the theoretical, feature-scope sense.
The next phase is hardening and bug fixing, not a new feature roadmap.

This is not a claim of security certification, complete Discord parity, or
universal hardware compatibility. Existing gaps must be fixed, validated, or
clearly bounded before 1.0; calling the scope complete does not erase them.

Build 106 passed all four CI targets (Linux, Windows, Android, Web/PWA), was
published as Latest on GitHub and deltie.net, and was deployed to chat.deltie.net.
Local regression results were 366 passing tests, one existing skip, and clean
static analysis. Compilation and automated tests are evidence, not substitutes
for physical-device or multi-client testing. Stable was not promoted.

## Release gates

- [ ] Account safety: password and discovered SSO/OIDC sign-in, cancellation,
  refresh/relaunch, logout, device verification, recovery and upgrades preserve
  sessions and encryption keys. Never fix a failure by silently resetting data.
- [ ] Security: review Android encrypted-database migration, attachment integrity,
  links/previews, imports, permissions and browser callback handling. Complete
  the pending operator callback rule before hosted browser SSO is used.
- [ ] Lifecycle: repeated background/foreground and network changes preserve
  timely timelines, typing, receipts, room lists, themes and media playback.
- [ ] Notifications: foreground suppression, dismissal, cadence reset, silent
  updates, invitations and thread navigation work on real devices, including
  installed iOS PWAs. Exercise distributor and permission failures.
- [ ] Messaging: media, spoilers, edits, rich composition, albums, voice messages,
  emoji/sticker imports and shared packs survive navigation and retry paths.
- [ ] Collaboration: two-client encrypted threads/forums, older history, unread
  state, notification taps and legacy-client fallback rendering are verified.
- [ ] Administration: owner/moderator/member boundaries, multiple roles, shared
  child rooms, manual overrides and partial propagation failures are tested.
- [ ] Presentation: global/server profiles, crop previews, keyboard/safe-area
  changes, small screens, large text, themes, contrast and reduced motion are
  reviewed on physical devices. Windows paste/send must not leak styles.
- [ ] Performance: measure browser input latency, large-account recovery, memory,
  image-heavy scrolling and media/RTC resource cleanup. Keep sensitive scroll
  changes in controlled test builds until evidence supports them.
- [ ] Distribution: verify signed Android upgrades, Windows shortcuts/installer,
  Linux dependencies, PWA cache updates, rollback and current documentation.

## Boundaries to keep honest

- Threads share room access; independent private-thread membership and locks
  are not implemented. Forum Following organises posts, not push subscriptions.
- Matrix numeric power levels remain authoritative; roles do not create arbitrary
  independent Discord-style allow/deny permission combinations.
- Scheduled sends need this client connected; they are not a server scheduler.
- Other clients may ignore namespaced presentation metadata. Ordinary messages,
  media and standard protocol events remain the interoperability baseline.
- Native macOS/iOS packages are not published. Their supported delivery route
  here is the web/PWA target, with browser storage and OS limitations.

## Reporting and triage

Report exact build, platform/browser, encryption state, reproduction steps,
expected/actual behaviour, frequency and lifecycle/network conditions. Redact
user content and never include tokens, recovery keys or private media URLs.
Separate reproducible defects from unverified suspicions and intentional limits.
Record validation evidence before closing an issue; a successful build alone
does not prove a behavioural fix.

See [known issues](../KNOWN_ISSUES.md), [build 106 scope](build-106-plan.md),
[security review](build-103-security-review.md) and [platform guides](README.md).
