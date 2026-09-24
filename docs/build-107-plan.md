# 0.9.34+107 implementation and validation

Status: published as Latest on GitHub and Deltie; PWA deployed to
`chat.deltie.net`. Release tag: `v0.9.34-b107`, source commit `5ba5050`.

## Behaviour and compatibility

Channel access uses Matrix join rules, history visibility and directory APIs.
Space policy is shared declarative state (`net.deltiecord.space.policy`): new
channel access defaults and cosmetic timeline-event visibility. Room overrides
take precedence over Space defaults, then personal preferences. Other Matrix
clients need not honour these display preferences. Existing channels are changed
only by the explicit, confirmed bulk action; public access is never silently
enabled. Restricted access allows Space members to join, not automatic joining.

Roles retain their existing shared state format. Edits compare a fresh snapshot
to the reviewed draft and reject stale saves. This is not an atomic server-side
compare-and-swap. Role definitions and explicit child-room power propagation
remain separate; inaccessible targets produce partial-failure reports.

Receipt aggregation retains readers from either global or main-thread positions
instead of overwriting a newer position with an older one. Public marker writes
still respect the user's receipt preference, foreground state and visible/latest
timeline guards. Windows-specific failure reproduction remains outstanding.

Mobile media paging shares downloaded image futures within the gallery, supports
zoom and spoilers, and keeps save/reference/favourite controls. Albums begin a
visible author group and do not span calendar-day boundaries.

## Validation

- Static analysis passed; 372 Flutter tests passed, one skipped; 25 server tests
  passed. Linux, Windows, Android and Web/PWA CI all passed on the tagged commit.
- All ten published artifact checksums verified before Deltie deployment;
  public PWA version and release manifest both confirmed build 107.
- The first Web CI run compiled successfully but timed out in a RAF-polled
  browser test even though the form switched modes. DOM polling fixed the test;
  the corrected commit passed browser autofill, mode switching and validation.
- Regression coverage: receipt stream ordering, album author headers on desktop
  and mobile, gallery swiping, Windows-target accent/icon/hover colours.
- Still required on devices: Windows-to-Linux/Android read receipts; Windows
  accent changes; small-screen profile/permission layouts; mobile zoom/swipe and
  video transitions; multi-account Space access, shared filters and role updates;
  startup update prompt against a published newer build.

## Explicit boundaries

GPU tuning remains deferred: sampled high usage did not have a confirmed trigger.
Guest-access controls and room-version upgrades are not added by this patch.
No live server configuration, memberships, permissions or account state were
changed during implementation. Publication updated the download manifest and
atomically switched the PWA to build 107. Stable remains unchanged.
