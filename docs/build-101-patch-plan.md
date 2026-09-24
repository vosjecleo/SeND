# Build 101 patch queue

> Historical record: observations, plans and validation below apply to the named
> build/date. For the current 0.9.34+106 milestone, see the [documentation index](README.md)
> and [1.0 hardening checklist](RELEASE_READINESS.md). Open validation items are
> not automatically resolved by a later release.

Implementation baseline: 0.9.30+100. The changes below are implemented for 101;
automated validation is recorded in the changelog and release handoff. Physical
device notification delivery and large-account/iOS performance still need runtime
validation. The parked HTML adapter and worker experiments are not included.

## Performance

- Separate first-recovery freezes from steady-state account overhead and browser
  software-rendering fallback. See `web-performance-build-100-account-investigation.md`.
- Measure recovery, key imports, sync processing, database activity and listener
  fan-out before choosing fixes. Preserve the existing Flutter UI and timeline
  scroll behavior during investigation.
- Validate on actual Safari/iOS, not just Chromium or Linux WebKit emulation.

## Desktop room-list header and inbox

- Reduce Home/server-title size to accommodate a search field.
- Place inbox and plus actions to the right of search, matching mobile structure.
- Make the inbox available on desktop, including accepting/ignoring invites.
- Add a small red dot at the inbox icon's top-right while an invite is pending.
- Verify badge updates after invite arrival, acceptance and ignore on both layouts.

## Mobile invite notifications

- Investigate the complete invite path: homeserver push rules/payload, gateway,
  native receiver/worker, filtering and notification presentation.
- Make eligible chat invites produce mobile push notifications, with correct
  navigation and clearing. Do not assume invites are ordinary joined-room messages.

## Live room-panel updates

- Fix category collapse/expand so the visible panel updates immediately.
- Fix voice membership counts for local and remote joins/leaves.
- Fix local connected/disconnected presentation immediately after disconnect.
- Check both mobile and desktop; navigation must not be necessary to refresh.
- The reports suggest a shared subscription/rebuild boundary, but verify the
  cause before treating all symptoms as one bug. Avoid broad forced UI resets.

## Voice-channel entry

- Clicking/tapping a voice channel opens its participant/overview screen first,
  including when not connected. Joining requires an explicit action there.
- Preserve the existing overview for an already-connected channel.
- Test that simply inspecting a channel never starts capture or joins a call.

## Acceptance checks

- Desktop and mobile header layout, narrow widths and text scaling.
- Pending invite badge, accept/ignore, live arrival and push navigation.
- Category collapse without opening another room, including after background/resume.
- Two-device voice joins/leaves and local disconnect without navigation.
- Recovery and warmed-session performance measured separately; no claim of iOS
  parity without device testing.

## Recent attachments (added during implementation)

- Query accessible device-wide photos/videos in modification-date order instead
  of relying on a vendor's all/camera album; retain bounded thumbnail paging.
- Explain limited media permission and allow choosing more accessible photos.
- Android permissions and media indexing still determine which downloads and
  screenshots can appear; private/unindexed folders cannot be bypassed.
