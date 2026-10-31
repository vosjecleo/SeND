# Test suite audit

Audit baseline: `e843555`, 2026-10-29–30. This is an engineering record, not a
release checklist. No application code, version, sessions or user data changed.

## Scope and decisions

Reviewed all 221 Dart test suites and their five support/configuration files,
the browser scripts and probes, server and packaging tests, Android JVM tests,
the WebRTC logging contract and all seven existing Actions workflows.

The [case ledger](test-suite-audit.csv) records each original Dart declaration,
including its parameter loops, decision and destination. It also lists external
test cases and operator-run probes. Declarations are not runtime test counts:
one parameterized declaration can register many cases. Internal assertions are
not counted as separate tests.

Most coverage is worth keeping. Similar-looking cases often exercise different
boundaries: stale versus concurrent writes, missing versus wrong encryption
keys, foreground versus headless notifications, native versus browser storage,
or receipt streams with different scopes. Those cases remain.

### Removed protection that was redundant or unused

- Four generated avatar pixel cases exercised proposed repaint-boundary and
  offscreen-layer strategies that the app does not use. Both production sizes
  still run through 36 animated frames, with an unclipped positive control that
  proves the escaped-pixel detector works. The frame-lifetime stress test stays.
- The separate “desktop and mobile GIF avatars advance frames” case repeated
  the autoplay-on checks already made for both adapters by the policy test.
  That test also checks pause/resume and reduced-motion precedence.
- The custom-emoji pack-size constant assertion duplicated the actual 150-item
  acceptance and 151-item rejection checks in `pack_reorganization_test.dart`.
  The separate Telegram protocol limit guard stays.
- The corner-radius/type-size constant test did not exercise a surface, layout
  or user action. Actual geometry, overflow and accessibility tests stay.
- Three TURN-cache cases exercised the retired `RefreshingVoIP` peer-to-peer
  adapter. Neither that adapter nor `TurnCredentialCache` has an application
  import or caller. Current MatrixRTC transport, lease, reconnect and encryption
  tests stay. The unused production adapter was not changed by this audit.

No current security, data-recovery, codec, notification or MatrixRTC failure-path
test was removed as redundant.

### Rewritten checks

Three Android source-string cases became parsed configuration checks in
`packaging/test_android_configuration.py`. The checks resolve manifest resource
references and validate each backup policy separately. The old test searched
the combined legacy/modern text and could miss a hole in one policy. The new
checks also bind receiver actions and share MIME types to the intended component,
instead of accepting matching text anywhere in the manifest.

Other changes:

- Removed duplicate assertions and a tautological object-identity check, while
  keeping the surrounding regression tests. Removed the obsolete v0.4 settings
  label/absence check, retaining navigation and account-identity assertions.
- Removed assertions about `ChoiceChip`, the `MaterialApp` wrapper identity,
  theme animation duration and a one-pixel drag-handle transform. Observable
  selection, immediate theme changes, stale callbacks and dragging still run.
- Day-separator checks retain centered labels, equal line lengths and symmetric
  in-bounds edges without requiring a particular 14-pixel inset.
- The category permission test now checks the current **Edit category** and
  **Delete category** actions, rather than the obsolete **Rename category** label.
- Attachment-text parsing uses a database-denying fixture instead of opening
  SQLite. These tests must not need storage access. Real database tests remain.
- Activity, Last.fm HTTP and RTC wire fixtures moved into `test/support/`.
  No test suite imports another test suite for setup.

### Historical suites

Build 103–118 and hotfix 127 cases moved to their feature owners: formatting,
receipts, appearance, authentication/logout, profiles, onboarding, media,
navigation and notifications. The mixed bug-pass and web-patch files were split
the same way. All input variants remain unless listed above. Live navigation
and activity-surface suites now have subject-based names instead of build or
preview numbers. The ledger preserves original locations.

## CI ownership

| Work | Before | After |
| --- | --- | --- |
| Full native Dart suite | Debian, Arch, Android's Ubuntu host, Windows | Validation, once |
| Format and analysis | Four native jobs, plus web analysis | Validation, once |
| Windows OS coverage | Mixed into the full suite | 30 native I/O, codec and rendering suites |
| Android JVM protocol tests | Present, not invoked by Actions | `:app:testReleaseUnitTest` after the release build |
| Server tests | Full web run plus repeated Debian Giphy subset | Validation, once |
| Packaging/configuration unit tests | Linux subset only | Validation, including root packaging tests |
| Browser bridge/worker unit tests | Web build | Validation |
| Browser/runtime tests | Web build | Web build, retained |
| Installed-package/sandbox checks | Platform package jobs | Retained |

The web job also runs the existing download-page and RTC-worker browser tests,
which were not wired into it. The bridge unit job now runs the existing viewport
and performance-probe checks. Web reuses the checksum-verified Flutter archive
cache instead of downloading the same SDK every time.

Package builds may run alongside validation. Publishing cannot proceed until
validation passes for the same commit, including web-only releases. Standalone
Flatpak/AppImage publication uses the same gate. Its tests reject missing,
pending, failed, cancelled, skipped and wrong-commit results; an older success
cannot mask a newer failed rerun.

No path filter or new test skip was added. Package launch, installation,
uninstallation, checksum, signature, sandbox and dependency checks remain.

## Measurements and validation

| Suite | Before | After | Local result |
| --- | ---: | ---: | --- |
| Native Dart runtime cases | 923 | 910 | 906 passed, same four skips |
| Chrome Dart cases | 18 | 18 | All passed |
| Server Python cases | 71 | 71 | All passed |
| Root packaging/configuration cases | 4 | 12 | All passed |
| Linux packaging cases | 17 | 17 | All passed, including the real zsync generator |
| Node bridge/worker checks | 22 | 22 | All passed |
| Browser integration scripts | 7 | 7 | All passed |
| Kotlin protocol cases | 3 | 3 | All passed on host JVM |
| Rust Megolm case | 1 | 1 | Passed |
| Java/WebRTC AAR contract | 1 | 1 | Passed |

Before counts outside the native suite are inventories of the unchanged suites,
not separate historical execution results. Chrome includes the six signature
cases also run natively, since the JS cryptography path needs its own check.
Script counts refer to executable scenario suites, not their internal assertions.

Dart declarations fell from 839 to 830. Dart test files increased from 221 to
228 because mixed historical files were split by feature. Four shared fixture
files were added. This audit did not target a file or test count.

Local native timings, from the test runner's JSON completion event:

- Baseline: **461.14 seconds**, 919 passed and four skipped.
- First cleanup pass: **466.35 seconds**, 909 passed and four skipped.
- Final pass, after removing the unused TURN tests: **637.69 seconds**, 906
  passed and four skipped.

These runs used one worker, a 4 GiB memory ceiling and a two-core CPU quota.
They were not isolated performance benchmarks. The final run was slower even
for unchanged cases; the cause was not established. No local runtime improvement
is claimed. CI now avoids three repeated full-suite executions. The first GitHub
timing observations after publication are recorded below.

Analysis and formatting passed. All eight workflow files parsed, their job
dependencies resolved, and 50 embedded shell blocks plus the packaging scripts
passed shell syntax checks. Windows PowerShell/package execution was not run on
this Linux laptop. The new Android Gradle task was not run locally; its three
pure protocol tests were compiled against the unchanged protocol object in an
isolated host-JVM fixture, without building the Android plugins.

The full-app autofill check initially timed out against an older local web
bundle. It passed with a fresh bundle built using the release's existing
JS-only/local-resource flags. The test now captures bounded startup diagnostics
and the existing failure screenshot instead of reporting only a missing selector.
The other browser checks covered authenticated worker decryption, storage
migrations and interrupted imports, RTC crypto vectors, download-page metadata
and actual WebCodecs output. No production behaviour was changed to pass them.

## First published CI run after cleanup

Build 135 (`c02c434`, 2026-10-31) passed all required workflows on the first
attempt. The later user-requested UI and sound work added regression cases;
this release ran 975 native tests with the same four skips. That is separate
from the audit-only 906-test result above.

Workflow wall times, from GitHub's `run_started_at` and `updated_at` timestamps:

| Workflow | Build 134 | Build 135 |
| --- | ---: | ---: |
| Shared validation | Not separate | 7m 13s |
| Windows | 17m 37s | 11m 19s |
| Linux packages and AppImage smoke | 13m 06s | 10m 10s |
| Android | 18m 51s | 15m 58s |
| Web/PWA | 9m 12s | 7m 45s |
| Signed GitHub publication | 45s | 1m 23s |
| Flatpak build and publication | 3m 14s | 3m 18s |

The slowest required package workflow fell from 18m 51s to 15m 58s. Validation
ran alongside packaging; it did not add seven minutes after the package jobs.
These are observations from two different commits, runners and cache states,
not an isolated benchmark or a promise about future builds.

Sources: [build 134 Android](https://github.com/VosjeCleo/SeND/actions/runs/40791487520),
[Windows](https://github.com/VosjeCleo/SeND/actions/runs/40791487519),
[Linux](https://github.com/VosjeCleo/SeND/actions/runs/40791487540),
[Web](https://github.com/VosjeCleo/SeND/actions/runs/40791487566);
build 135 [validation](https://github.com/VosjeCleo/SeND/actions/runs/41155182307),
[Android](https://github.com/VosjeCleo/SeND/actions/runs/41155182309),
[Windows](https://github.com/VosjeCleo/SeND/actions/runs/41155182305),
[Linux](https://github.com/VosjeCleo/SeND/actions/runs/41155182298),
[Web](https://github.com/VosjeCleo/SeND/actions/runs/41155182365),
[publication](https://github.com/VosjeCleo/SeND/actions/runs/41156478932) and
[Flatpak](https://github.com/VosjeCleo/SeND/actions/runs/41156593738).

The first mirror attempt stopped because the old channel metadata was unsigned.
After checking that legacy metadata over SSH and against the published download
hashes, the documented one-time signing bootstrap completed. New signatures,
artifact hashes, PWA metadata and unchanged Stable lists were verified live.

## Remaining gaps

- Android notification publication, bitmap allocation, wake-service lifecycle,
  keyboard inset wiring and stable identifiers still have source-contract
  guards. They are brittle, but remain the only automated checks for several
  security invariants. Replace them only with equivalent compiled/device tests.
  Persistent client identities, publisher/client trust-key parity and some
  cross-language push wiring also retain source guards for that reason.
- Passing simulated clipboard, IME, lifecycle or haptic tests does not prove
  physical Gboard, OEM background execution or iOS behaviour. Real-device tests
  remain necessary. Chromium's Apple-vendor routing test is not WebKit coverage.
- The avatar containment and lifetime tests do not reproduce every GPU-driver
  flicker. Do not treat their success as proof that the reported flicker is gone.
- Windows named pipes and native libraries need Windows execution. Cross-platform
  logic is checked once; real I/O is deliberately repeated on Windows.
- Optional live preview, private GIF and host-MPRIS probes remain opt-in. Live RTC
  probes create temporary server state and are not part of ordinary CI.
- Several controller tests still use short real-time waits. They were not deleted
  or shortened to win a benchmark; deterministic clock injection is a separate,
  focused improvement when those controllers next change.
- Browser scripts combine multiple scenarios in a single process. Splitting them
  into independently named cases would improve failure reporting, but must retain
  their migration, corruption and interrupted-transaction checks.
- The AppImage repackage workflow is pinned to build 112. Its Nix regression
  reproductions remain a historical/manual path, not evidence that every current
  AppImage release is tested on NixOS.
