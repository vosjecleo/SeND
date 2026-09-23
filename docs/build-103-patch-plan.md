# Changes for version 0.9.31+103

Status: implementation regression-tested; CI build and latest publication authorized.
Baseline: 0.9.30+102 PWA / 0.9.30+101 native releases.
User authorized CI-only builds, GitHub/deltie.net latest publication and PWA
deployment on 2026-09-24. No local builds; stable remains unchanged.
Append new reports here; do not silently treat proposals as completed fixes.

## Implementation handoff

See CHANGELOG.md for implemented changes and build-103-security-review.md for
security boundaries and remaining validation. The requirements below remain the
original acceptance checklist, not a claim of device-level verification.

- Added final request: vertically center desktop timeline avatars on the first
  sender-and-message line; continuation messages do not gain redundant avatars.
- iOS/PWA-specific work (section 16 and the separate investigation below) is
  explicitly deferred to tomorrow's build, including camera/image attachments.
- Initial implementation stopped after the source-only push. The subsequent
  authorized release uses CI artifacts and the existing atomic PWA deployment.
- Resume/theme propagation is covered by simulated lifecycle tests; actual
  Android freeze/unfreeze reproduction remains a manual validation gate.
- Existing rich-message formatting loss and custom-emoji/Markdown interaction
  are fixed. FluffyChat uses a Markdown insertion editor; we retained Quill and
  the existing mobile text field instead of introducing an editor replacement.
- Usage counts only successful normal sends; edits do not increment counts.
  Failed messages retried directly through the SDK are not retroactively counted.
- Password changes use the SDK's password reauthentication flow. SSO-only or
  other server-specific authentication flows need separate runtime validation.

## 1. Inline receipts and edit markers

- Move receipt indicators from their current position to immediately after the
  message text, on both desktop and mobile (including corresponding web layouts).
- Move edited markers to the same trailing position.
- Requested ordering:
  `This is some message content (read receipt) (edited) (edit read receipt)`.
- Keep indicators legible and correctly positioned for multiline text, inline
  custom emoji, RTL text and enlarged fonts. Wrap gracefully without clipping
  text or overlaying media. Define placement for media-only messages.
- Present receipts as progress boundaries rather than repeating them on every
  outgoing message. Older messages inherit the state indicated at a later
  boundary: "sent and read from here and up", then "sent only from here to
  sent and read".
- Preserve actual SDK receipt/send state. A UI change must not invent read
  acknowledgements, change protocol behavior, or hide pending/failed sends.

Confirmed: the sent marker advances to the latest successfully sent message;
the read marker advances to the latest outgoing message acknowledged as read.
Do not leave the sent marker on the first unread message. When both frontiers
coincide, show the combined sent/read state rather than redundant markers.

Example, corrected following the user's clarification:

```text
me:   hey!!           (no receipt, implies sent + read)
yeen: hello
me:   Hi              (sent + read)
yeen: How are you?
me:   doing good      (no receipt; within the sent-but-unread range)
me:   what about you? (sent)
```

Clarifications needed before implementing receipt selection:

- How should the "edit read receipt" be determined? Inspect replacement-event
  receipt behavior before assuming that reading the original means reading its
  edit, or that every other client acknowledges edits separately.
- Specify group-chat behavior (per-person read frontiers versus an aggregate),
  and whether boundaries are scoped to the current thread/timeline.

Acceptance checks: two-user conversation matching the example; multiple sends
before/after a read; original read then edited; pending/failed send; history
pagination; live receipt updates; groups; narrow widths and text scaling.

## 2. Space/server settings transitions

- Regression remains: some animations enter/exit from the wrong side, and text
  sometimes overlaps during transitions.
- Trace forward/back navigation, clipping and outgoing/incoming child layout.
  Do not assume the earlier transition fix covered every route.
- Check repeated navigation, interrupted transitions and reduced-motion mode.
- Acceptance: consistent direction for forward/back, no simultaneous text
  overlap, correct clipping, instant transitions with Reduce Motion enabled.

## 3. Desktop composer height and alignment

- Grow the composer as the draft gains lines. Choose a sensible maximum height,
  after which the draft scrolls internally rather than consuming the timeline.
- Keep the user island and "View full profile" button at their own fixed
  heights: they must not stretch along with the composer.
- Correct the desktop draft text's vertical centering, matching the mobile
  polish. Preserve its horizontal alignment with timeline message content.
- Check empty/single-line/multiline drafts, edit/reply states, long unbroken
  text, custom emoji and accessibility scaling.
- Preserve bottom alignment of the independent islands. Check typing indicator
  clearance and latest-message visibility without a broad scroll-system rewrite.

## 4. Responsive mobile controls and settings

- Pixel 8 looks correct, but narrower and larger phones have layout problems.
  Audit controls at multiple logical widths rather than special-casing devices.
- In rows of buttons/fields, reflow whole controls onto additional rows before
  labels wrap awkwardly, clip or spill inside fixed-size controls.
- Theme controls should become a 2-by-2 grid when four across do not fit; allow
  a single column if even two cannot fit at a large accessibility text scale.
- Preserve intentional multiline descriptions and multiline text-entry fields;
  this request is not a blanket ban on wrapping all text.
- Prefer available-width/text-size constraints, adequate field height and usable
  touch targets. Do not shrink fonts just to conceal overflow.
- Test approximately 320, 360, 390, 412 and 480 logical pixels, wider/tablet
  layouts, portrait/landscape, the default mobile scale and larger text scales.
- Acceptance: readable complete labels, no overflow, natural control wrapping,
  no unnecessarily cramped layout on larger devices.

## 5. Notification/call sound refresh

- User supplied sound candidates (not yet integrated):
  - `/home/cleo/Documents/Notification.flac`: approximately 0.597 seconds,
    mono, 22,050 Hz, 16,672 bytes.
  - `/home/cleo/Documents/Ringtone.flac`: approximately 1.071 seconds,
    mono, 22,050 Hz, 29,208 bytes.
- Confirmed by user: both are their own creations and are intended to replace
  the current credited placeholder sounds. In the next sound-replacement commit,
  remove the obsolete HaelDB/UI Sounds credit from `CREDITS.md` once those
  placeholder assets are no longer shipped. Preserve unrelated credits and
  attribution for any retained assets; no third-party credit is needed for
  these newly supplied sounds.
- Preserve these source files. Before packaging, audition volume and ringing
  repetition/gaps, verify playback-format support for each intended platform,
  and update credits as above. Metadata checked; audio not yet auditioned.
- Desired character: minimalist, soft, sine-based sounds.
- User prefers a dedicated game sound-effect synthesizer with more direct
  synthesis control than the suggested Audacity tone/fade workflow.
- User will design/review candidates before choosing packaged replacements.
  Keep sound assets easy to swap; do not change existing platform sound policy
  or notification cadence as an incidental part of replacing audio assets.
- Candidate tools:
  - LabChirp: up to eight channels, editable envelopes, modulation and custom
    waveforms. Windows application; Linux through Mono.
    https://labbed.itch.io/labchirp
  - Bfxr: dedicated game SFX generator with randomization/mutation, saved
    presets and WAV export. https://www.bfxr.net/
  - jsfxr: lightweight browser generator with sine waveform, envelope controls,
    WAV export and reusable presets. https://sfxr.me/
- Suggested starting experiment, not a final specification: 150–300 ms sine
  tone around 600–900 Hz, short gentle attack, longer fade-out, modest volume;
  optionally a second quiet note. Avoid clipping and abrupt waveform cuts.
- Save editable originals/presets alongside final exports; record authorship
  and any required credits. Compare loudness on phone speakers/headphones and
  test repeated call playback for harshness or clicks.

## 6. Security and privacy audit

Added September 24. These are reported concerns, not yet confirmed findings.
Inspect the CURRENT implementation and SDK behavior before choosing fixes.

- Local timeline cache: inventory databases and other persistent stores for
  decrypted messages, media, session credentials and crypto material. Check
  Android backup exclusions, private permissions, logout cleanup and web/native
  differences. Document what access to an app directory would actually expose.
- Where supported and practical, use established encrypted storage with
  OS-protected keys; do not invent cryptography. Plan migration and recovery
  before changing existing stores. App sandboxing and Matrix E2EE alone must not
  be described as encryption of the local timeline cache; also document the
  limits of storage encryption on an unlocked or compromised device.
- Formatted links: reveal the actual destination before opening, particularly
  when visible text differs from the target. Show a readable scheme/host and
  inspectable full URL; reuse safe URL validation and test misleading labels,
  Unicode hosts and unsupported schemes.
- Video attachment integrity: trace streaming, range requests, encrypted-media
  proxying and SDK downloads to verify whether declared SHA-256 is checked.
  For encrypted Matrix attachments, verify the ciphertext against the declared
  hash, not a hash of the decoded/decrypted video. Do not confuse an ordinary
  attachment without hash metadata with an integrity failure.
- If integrity verification is missing, specify a bounded verification/cache
  strategy and reject mismatches. Explicitly account for the fact that a whole-
  file hash cannot authenticate early streamed bytes before the file completes;
  do not promise verified-before-playback streaming without addressing that.
- Add regression coverage for any storage migration/cleanup, link confirmation
  and attachment integrity changes. Report findings and remaining limitations.

## 7. Mobile channel/category alignment

- Align mobile channel hash symbols and category dropdown text to the same
  intended column, matching the desktop layout. Check expanded/collapsed
  categories, long names and larger text sizes without changing desktop spacing.

## 8. Settings organization and account security

- Increase settings entry font size modestly, retaining the responsive wrapping
  and accessibility requirements in section 4.
- Group entries under visible section headings:
  - Account: Account, Devices, Security.
  - Preferences: Audio & Video, Appearance, Accessibility, Privacy.
  - App: Notifications, Storage, About.
- Inventory all existing entries and place any omitted ones in the appropriate
  section; do not silently remove functionality during the reorganization.
- Fold Encryption into Security, preserving existing verification, recovery and
  key-management functionality. Add account password changing there.
- Inspect FluffyChat's current password-change flow and reuse the Matrix SDK's
  authentication/password APIs. Handle required reauthentication, server errors,
  password-manager integration and any other-session logout choice explicitly;
  never log passwords or bypass server authentication requirements.

## 9. Reliable logout and UI reset

- Always ask for confirmation before logout. Cancel must leave the account and
  UI untouched; guard against repeated taps while logout is in progress.
- On successful logout, dismiss settings and all account-specific overlays and
  return to a clean signed-out screen. Clear account-scoped UI caches and dispose
  subscriptions/controllers so stale rooms, profiles, themes or timeline state
  cannot survive into the next login.
- Audit persistent private-state cleanup through the existing session/storage
  owners, preserving unrelated accounts and deliberately exported user files.
  Handle logout failures explicitly rather than showing false success.
- Test logout from nested settings, after resume, cancellation, failure and
  signing into another account without restarting the app.

## 10. Mobile appearance colour picker

- Present the picker nearer the centre of the screen, with safe-area and
  small-screen/text-scaling constraints rather than pinning it near the bottom.
- Add an obvious Apply button that simply closes the picker. Colours continue
  applying live as they do now; this is an affirming dismissal action, not a new
  deferred-save or rollback model.

## 11. Theme/layout updates after freeze and resume

- Recurring mobile regression: after several background/freeze/resume cycles,
  theme, resizing and related appearance changes stop updating the visible UI.
  Prior fixes have not reliably resolved it; reproduce against the current tree.
- Trace lifecycle observers, preference listeners, subscriptions, stale widget
  state and rebuild propagation. Distinguish settings being saved from settings
  actually reaching all mounted surfaces, including navigation and overlays.
- Fix the lifecycle/state ownership problem rather than applying periodic full
  resets or clearing sessions. Preserve drafts, room selection and the user's
  local-versus-synced appearance preferences.
- Regression test repeated resume cycles followed by theme, colour and text-size
  changes, including changes while settings are already open. Check native
  Android and the PWA separately and record any device-only validation needed.

## 12. WYSIWYG composer correctness

- Report: the current WYSIWYG implementation is broken; specific failing cases
  still need reproduction. Inspect FluffyChat's current editor implementation
  alongside Deltiecord's before deciding on fixes, rather than assuming an
  editor replacement is required.
- Trace draft editing, selection/caret behavior, formatting, paste, custom emoji
  tokens, edit/cancel and outgoing Matrix plain-text/formatted-body generation.
  Include mobile IME/composition and desktop keyboard interactions.
- Add focused regression cases for reproduced failures and preserve compatible
  Matrix message formatting, literal/escaped text and safe formatted rendering.

## 13. Room header and menu parity

- Keep Search and Start call visible outside the three-dot menu on desktop and
  mobile, subject to the room's supported call actions and permissions.
- Give mobile the same primary header actions as desktop. Move mobile-only
  header actions into its three-dot menu rather than leaving divergent layouts.
- Inventory existing actions, remove redundant placements and organize the menu
  with clear labels and logical groups. Preserve useful functionality rather
  than silently dropping actions during simplification.
- Test narrow screens, long room names, text scaling and room/DM differences.

## 14. Emoji and sticker favourites and usage

- Frequently used emojis must reflect what is actually sent, not picker clicks.
  Count Unicode and selected custom emojis from the outgoing message, including
  supported colon lookups that resolve to emojis. Do not count removed draft
  items, cancelled sends or literal/escaped unresolved lookup text.
- Define a single send-based accounting point with retry/local-echo
  deduplication. Cover typed/pasted emojis as well as picker selections; decide
  and document edit handling so unchanged content is not counted repeatedly.
- Add or repair sticker favouriting through the existing pack/item identity and
  favourites infrastructure. Add frequently used stickers based on actual sends.
- Order emoji and sticker picker sections: Favourites, Frequently used, then
  the whole catalogue. Preserve pack organization and unavailable-item handling.
- Test select-then-backspace, lookup-then-send, failed/retried sends, duplicate
  custom emoji names across packs, and adding/removing sticker favourites.

## 15. GIF favourites presentation

- Show the favourite/unfavourite action only in the fullscreen GIF viewer on
  desktop and mobile; remove its inline and picker placements without losing
  the ability to open a GIF fullscreen and favourite it there.
- In the GIF picker, show Favourites before Trending. Give Favourites its own
  visually distinct labelled category/container, not an undifferentiated row
  above trending results. Preserve GIF search and existing saved favourites.

## 16. Mobile PWA camera and image attachments

- Report: selecting images currently does not attach them, including through
  the in-app picker. Trace browser file selection through draft attachment state,
  preview, upload and send; do not treat this as only a missing camera button.
- Provide usable camera capture and image-library/file selection in mobile PWA,
  using browser-supported input/capture APIs and appropriate fallbacks. Do not
  assume native photo-library plugins work on web or that browsers honor capture
  hints identically.
- Test installed iOS/Safari and Android PWAs, permission denial, cancellation,
  selecting the same file again, multiple images, camera return/resume and
  supported phone image formats. Preserve drafts across picker interruptions.
- Selected supported images should visibly attach, preview and send; failures
  should produce actionable feedback rather than silently doing nothing. Keep
  attachment validation, resource bounds and encrypted-room upload behavior.

## Existing iOS reports — investigation pending hands-on testing

These remain tracked, not diagnosed or promised fixed in this release yet:

- iPhone 13 Pro: lag after opening/reopening that suddenly clears later.
- Startup screen not always observed; distinguish cold load from suspended-page
  resume before drawing conclusions.
- Taps sometimes register above visible buttons. Keyboard tests have not yet
  established a reliable trigger; don't apply a fixed coordinate offset.
- Occasional apparent sign-outs: distinguish login form, key-recovery prompt,
  loading/empty UI, and actual session invalidation/storage loss.
- WebGL cube DOES spin (corrected report); do not describe WebGL as unavailable.
- Reported iOS version: 26.7; record exact device version/build during testing.
- User plans hands-on testing. Test sheet is saved at:
  `/home/cleo/Documents/Deltiecord-iOS-PWA-test-sheet.txt`.
- Potential diagnostic work: startup/resume phase timings, long-task counts,
  viewport bounds/offsets and non-sensitive session state. No credentials,
  recovery keys, tokens or message content in diagnostic output.

## Delivery checklist (for the eventual implementation)

- Resolve receipt semantics above before coding that behavior.
- Inspect current tree and preserve unrelated user changes.
- Add focused regression coverage for changed behavior and layout constraints.
- Format, analyze and run relevant tests/builds; verify real iOS behavior where
  required instead of treating Chromium-only tests as proof of Safari parity.
- Update the actual changelog with completed changes and honest limitations.
- Obtain/confirm final release scope and channel when implementation is requested.
