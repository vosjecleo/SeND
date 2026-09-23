# Build 100: browser and account-size investigation

Date: 2026-09-23. Baseline: `d0f99c8`, version 0.9.30+100.

## Scope and preservation

The working tree is back on build 100, on branch
`investigate/build100-web-performance`. Build 101 remains on
`dev/flutter-worker-pwa`; the untracked HTML prototype was preserved in a named
Git stash. Ignored generated prototype files were moved to a private backup
directory outside the repository. No application behavior, server configuration,
or deployment was changed during this investigation.

Tests used the hosted build 100, headful browsers, disposable browser profiles,
and the dedicated account supplied by the owner. No main-account credentials or
message history were obtained. Passwords/recovery keys were passed through
non-echoing stdin, not files, arguments, environment variables, or browser traces.
Browser profiles were closed afterward. Server-side logout was not confirmed for
the two authenticated test devices; disposable-profile removal is not token
revocation. Existing account devices were not deleted.

## Findings: keep three problems separate

### 1. LibreWolf can use software rendering before login — measured

On this host, isolated LibreWolf 150.0.2-1 rejected both WebGL1 and WebGL2
contexts with `WebGL is currently disabled.` Flutter logged its CPU-only
rendering fallback. This happened with `webgl.disabled=false`, RFP disabled,
and both with and without fingerprinting protection. Merely changing those
preferences did not establish a GPU context.

LibreWolf has a separate site-level WebGL permission. Its official FAQ describes
allowing context creation per site:
<https://librewolf.net/docs/faq/#should-i-allow-webgl-context-creation>.
The global preference alone is therefore insufficient evidence that the app
actually has WebGL. The user's normal profile was not modified, and its actual
site permission/rendering backend still needs to be checked. An isolated test
with `permissions.default.webgl=1` also failed to establish a context; do not
present that preference as a verified fix.

The local Flutter engine's `canvaskit/surface.dart` explicitly switches to a
software SkSurface when it cannot create the GL/Gr context. This explains how
the same UI can behave very differently from the native application.

### 2. Main-account recovery freeze — user-reproduced, not yet profiled

The owner reports Chromium login scrolling is smooth, but finishing recovery
makes the app temporarily unusable. Reloading makes it substantially better than
LibreWolf and usable, though slower than the fresh test account.

That distinguishes an initial restoration/decryption/update burst from ongoing
rendering cost. The dedicated account successfully logged in and recovered in
both browsers, but did not reproduce the main account's severe freeze. It cannot
represent an older account's key, device, room, and history volumes. Persistence
allowing a reload to reuse restored data is a plausible explanation, not proof
of which operation monopolizes the thread.

### 3. Account-dependent recurring work — source-confirmed candidates

* `matrix_session.dart`: every sync notifies the backend and schedules a metadata
  pass across all joined rooms. Existing coalescing prevents overlapping passes,
  but requests arriving during a pass cause another pass.
* `matrix_room_metadata.dart`: `_refreshAvatar` returns `true` for an unchanged
  absent/non-MXC avatar. Its unchanged check requires cached bytes. Avatarless
  rooms therefore cause redundant "changed" notifications on later passes.
* Room-summary presence calculation scans room participants; room summaries are
  reconstructed when the `rooms` getter is read. Larger accounts can amplify
  this work during global listener notifications.
* `matrix_room_operations.dart` starts `_loadRoomBackupKeys` when opening a room.
  `matrix_timeline_support.dart` calls `loadAllKeysFromRoom`, not a visible-session
  subset. The once-per-room guard is in-memory. The SDK imports returned sessions
  and emits key/decryption updates. This is a concrete potentially large workload,
  but is not established as the cause of the recovery-screen freeze: it applies
  when an encrypted room is opened.
* SDK 10.1.0's backup-secret cache callback retries decrypting last events across
  rooms after unlock. This is another account-size-dependent burst to measure.

No evidence was found that `restoreCryptoIdentity` itself indiscriminately calls
`loadAllKeys` for the entire account. Do not conflate that with the explicit
per-room backup import above.

Build 100 creates the SDK client on the UI thread. Its installed SDK
`NativeImplementationsWebWorker` handles image operations and explicitly falls
back for secret-storage checking. It does not relocate the whole Matrix client,
sync processing, key imports, IndexedDB, or all decryption into a worker.

## Measurements

Six-second requestAnimationFrame samples; headful browser family CPU totals
include child/GPU processes. 100% means one logical core. These are diagnostic
samples, not a comprehensive rendering benchmark: rAF cadence does not prove
every frame was painted or measure input-to-presentation latency.

| Scenario | rAF intervals | p95 interval | CPU, one-core equivalent |
| --- | ---: | ---: | ---: |
| Chromium 153 signed out, idle, DPR 1 | 361 | 16.7 ms | 13% |
| Chromium test account after recovery, idle, DPR 1 | 361 | 16.7 ms | 11% |
| Chromium signed out, scroll, DPR 1.5, 1280×420 | 359 | 16.7 ms | 127% |
| LibreWolf signed out, scroll, DPR 1.5, 1280×420 | 222 | 34 ms | 139% |
| LibreWolf same scroll, repeat | 248 | 34 ms | 145% |

The matched scroll tests disabled Flutter semantic-tree automation and used
20 alternating wheel inputs, then settling time. No Matrix sync ran in those
signed-out tests. Chromium reported Intel UHD 620 through ANGLE/WebGL2;
LibreWolf reported no WebGL context. Chromium's repeat scroll sample had no
long tasks over 50 ms, but about 2.73 seconds of script and 3.18 seconds of task
time over six seconds. Smooth does not mean inexpensive.

Firefox 156 did establish WebGL2 and showed intermediate scroll performance,
but its test had semantics enabled and a different engine version; it is not a
strict controlled comparison. Firefox does not expose Chrome's long-task
observer here; zero observed long tasks there must not be interpreted as none.

Some LibreWolf runs also produced startup permission/CSP errors and took longer
to create the Flutter view. Startup-incomplete samples were not used as app
performance evidence. Their source was not identified.

## Next controlled tests, before architectural changes

1. Verify successful WebGL context creation in the user's LibreWolf for this
   origin, then reload and compare the same account. Prefer a site permission,
   not globally disabling privacy protections. Test failure should be visible
   in a future diagnostics UI instead of silently implying GPU acceleration.
2. Capture a CPU-only sampling profile around main-account recovery and after
   reload. Do not collect network bodies, screenshots, DOM snapshots, or storage
   dumps containing private data. Obtain the owner's participation rather than
   requesting their recovery key.
3. Instrument only aggregate timing/counts: recovery stages, imported sessions,
   key-arrival callbacks, metadata passes, backend notifications, room-summary
   construction, and maximum event-loop delay. Separate network waiting from
   CPU/IndexedDB and Flutter build/raster work.
4. Independently test fixing the absent-avatar false-positive, bounded/coalesced
   notifications, and visible-session-first key loading. Preserve unread, sync,
   and decryption semantics and add regressions before deployment. Do not combine
   these with another UI rewrite or sensitive timeline-scroll changes.
5. If profiles show crypto/sync dominates after those changes, evaluate moving
   the complete Matrix owner into a worker behind a narrow protocol. Adding the
   image helper worker is not equivalent and cannot promise to solve recovery.

## Probe

`tool/web_performance_probe.mjs` is a local investigation tool, not shipped app
code or a CI benchmark. It requires Node and a separately installed
`puppeteer-core`; set `PUPPETEER_MODULE` to its entrypoint. Use an interactive
terminal with echo disabled for any credentials. It supports isolated Chromium,
Firefox and LibreWolf, aggregate frame/CPU sampling and WebGL checks. Inspect and
screenshot operations must only be used with the dedicated test account. It
must not be pointed at a personal authenticated browser profile.

Validation: `node --check` passed. Flutter analysis/tests were not rerun because
no application source or dependency changed.

## Follow-up: recovery update amplification

Further tracing confirmed this chain in SDK 10.1.0:

1. Unlocking the backup secret runs KeyManager's cache callback, which retries
   last-event keys across rooms.
2. `setInboundGroupSession` attempts to decrypt a room's last event. If successful,
   it calls `client.handleSync` with a synthetic room update to persist the result.
3. `Client._handleSync` emits `onSync`; Deltiecord's listener notifies the global
   backend and requests another full metadata pass, just as for network sync.
4. Each received room key is also broadcast to a live timeline. The SDK scans its
   events for matching encrypted sessions; successful decryption invokes timeline
   update callbacks, which Deltiecord uses to notify and request hydration.

This is a source-confirmed amplification path, not evidence that every imported
key triggers a global sync or that every notification causes a separate painted
frame. Metadata/hydration passes already coalesce; Flutter can coalesce builds.
Only keys that successfully decrypt the current last event take the synthetic
sync branch. Visible-timeline key callbacks apply only when a timeline is open.
The aggregate amount of work needs measurement on the affected account.

`_refreshPreview` also explicitly fetches a last-event backup key when the
preview cache is empty. This potentially overlaps the SDK's automatic request;
whether duplicate requests materially contribute remains unmeasured.

### Private-account sampling without sharing account access

`tool/web_runtime_probe.js` can be run as a browser DevTools Sources snippet on
the affected page. Review it first. It runs for 30 seconds and logs only:

- main-thread long-task aggregates, where supported;
- frame-callback gaps and 100-ms heartbeat delays;
- completed request counts/durations in fixed endpoint categories (sync, backup
  keys/version, device keys, account data, media, other).

It does not read message content, DOM fields, browser storage, request/response
bodies, keys or tokens; URLs are classified in memory and never exported. Do not
send full console logs or network exports: only its final aggregate JSON.

For an initial-recovery sample, start immediately before submitting recovery.
Keep the app tab visible and do not resize it during the sample. Compare with a
new sample after reload in the same browser, viewport and account. No need to
clear an established session just to reproduce recovery; use a separate profile
if the owner elects to repeat that test. Stop early with
`window.__deltiecordPerformanceProbe.stop()` if desired.

Limits: these counts include only completed requests, not failures or in-flight
requests; cache/service-worker behavior affects resource entries. Durations
overlap, so their sum is not wall time or crypto CPU time. Hidden-tab samples are
flagged and should not be compared to foreground samples. Missing long-task API
support is explicit. A blocked main thread can delay the 30-second stop timer.
The snippet cannot attribute a stall to a Dart function; CPU sampling or opt-in
app timing instrumentation is the next step if aggregates confirm a burst.

`node tool/web_runtime_probe_test.mjs` passes checks for aggregation, URL/secret
redaction, cleanup, idempotent stopping and unsupported API reporting.

### Safari/iOS

WebGL2 is supported from Safari 15, including iOS. CanvasKit's WebGL rendering
path is therefore available in principle; this is separate from Flutter's
WasmGC/skwasm compatibility. Support does not guarantee successful context
creation on every device or prevent main-thread crypto/update stalls. Actual
iPhone performance has not been tested in this investigation.

Source: <https://webkit.org/blog/11989/new-webkit-features-in-safari-15/>.
