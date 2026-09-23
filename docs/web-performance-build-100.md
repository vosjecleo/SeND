# Build 100: web responsiveness investigation

## Findings and scope

The reported problem is steady-state interaction latency, not cold startup.
No production credentials or recovery keys were used. Without an authenticated
test session or a browser performance recording of the failure, the two-minute
recovery delay cannot be attributed to a single operation.

Confirmed code paths:

- `lib/app.dart` rebuilt `ColorScheme.fromSeed`, `ThemeData`, and `MaterialApp`
  on every backend notification. Build 100 caches the configuration by relevant
  visual/window settings and session state, while the home subtree continues
  listening for chat updates. A regression test sends 25 independent backend
  notifications and verifies reuse plus invalidation on an appearance change.
- `matrix_session.dart` notified listeners on every SDK sync-status callback,
  even when the displayed connection status was unchanged. Only status changes
  now notify through that path; actual sync events continue to notify normally.
- Fresh authentication could expose default preferences before initial account
  data arrived. Preferences are saved as a whole document, making that a
  plausible reset path. Fresh login now waits for the initial sync; restored
  cached settings remain usable offline. Writes before hydration are rejected.
- Space settings used transparent pages sliding over each other, with another
  nested crossfade. Sequential fades on an opaque, clipped surface replace
  those transitions. Tests check that both pages are never simultaneously
  visible, and that Reduce Motion swaps immediately.

These are confirmed avoidable work/races, not measured percentages of the
reported lag. Theme reuse does not eliminate expensive work inside chat widgets.

## Encryption recovery

The pinned Matrix SDK checks initial sync/account data, restores secure-storage
secrets, and verifies the device. A passphrase also takes a derivation path with
a two-minute timeout; a recovery key follows a different path. That timeout is
not evidence that it caused the reported delay.

Build 100 shows the current coarse recovery phase and emits `TimelineTask`
markers containing fixed labels only. No key, passphrase, account identifier,
or server response is added to profiling events. Concurrent recovery requests
share one operation. All crypto and protocol operations remain SDK-owned.

To investigate further, use a dedicated account with encrypted history in a
profile build. Record a Performance/DevTools trace during recovery and normal
chat interaction; compare long tasks, frame time, request waits, and the named
recovery phases. Test a recovery key and a passphrase separately. Browser
profiling tools can capture other sensitive application data, so review traces
before sharing them. Do not record a production recovery credential.

## Deliberately deferred

- Timeline mapping and image dimension changes remain likely contributors to
  image-heavy scroll jitter. No scroll logic, row sizing, or media mapping was
  changed. Confidence in those candidates is moderate until a trace confirms it.
- Flutter web creates autofill form elements when an eligible field is focused.
  Existing username/password hints were already present. Removing the URL field
  from credential autofill is a conservative improvement, not proof that every
  browser password manager now works. Local Chromium inspection confirms that
  focusing username/password creates one form with `autocomplete="username"`
  and `autocomplete="current-password"`; the homeserver field uses `off` and is
  not in that form. Test Safari/iOS and actual Chromium password managers.
- Real-account settings restoration, recovery speed, installed iOS Web Push,
  and steady-state performance on physical mobile devices still need validation.

KLIPY proxy/rehosting behavior is unchanged: the owner reports written provider
approval. Search KLIPY attribution remains; favourites and standard Matrix media
interoperability are unchanged.

## Local validation

- Formatting and Flutter analysis: clean.
- Full Flutter suite: 273 passed, one existing skip.
- Release web build: successful, version `0.9.30+100` verified in its manifest.
  The compiler warns about a referenced Cupertino icon font missing from assets;
  icon rendering beyond the exercised paths still needs review.
- Fresh Chromium contexts at desktop and mobile-sized viewports render the
  canvas with cross-origin isolation and no uncaught JavaScript errors.
  This is a signed-out smoke test, not Safari/iOS or authenticated performance
  validation. No build-100 artifacts have been deployed.
