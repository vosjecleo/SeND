# Tests

Run the native unit and widget suite from the repository root:

```sh
flutter test --concurrency=1
```

CI uses two workers on its shared validation runner. Test files run
independently; each test must clean up timers, platform overrides, temporary
files and subscriptions. Do not rely on another test having run first.

## Layout

- Widget tests are grouped by feature, such as `profile_views_test.dart`,
  `space_categories_test.dart`, `composer_sending_test.dart` and
  `mobile_timeline_interactions_test.dart`.
- `support/fake_backend.dart` provides the shared in-memory chat backend.
- `support/widget_helpers.dart` contains mobile pumping, composer input,
  context-menu gestures and fake drag sessions. Helpers do not register tests.
- Service and protocol tests sit alongside the widget files. Browser-only tests
  declare `@TestOn('browser')`; the Web PWA workflow runs them in Chrome.
- Historical regressions live in feature suites, not build-number files.
  Their original locations and review decisions are in the
  [audit ledger](../docs/test-suite-audit.csv).
- Activity, Last.fm HTTP and RTC wire fixtures live in `support/`. Do not import
  one test suite from another to share setup.

Keep shared fixtures small and deterministic. Test observable behaviour rather
than source spelling. Simulated backends do not replace device checks for RTC,
notifications, codecs, keyboards or OS permissions.

Server tests use `python -m unittest discover -s server -p 'test_*.py'` with the
server dependencies installed. Configuration and publishing-gate tests use
`python -m unittest discover -s packaging -p 'test_*.py'`. Linux packaging tests use
`python -m unittest discover -s packaging/linux -p 'test_*.py'`.
The [workflows](../.github/workflows/) contain platform and browser commands;
[CI timings](../docs/ci-performance.md) records measured run times.

## CI ownership

`Validation` runs format checks, analysis, the full native Dart suite, server and
packaging unit tests, shell syntax checks and browser bridge/worker unit tests.
It runs once per main-branch push or pull request, including web-only changes.
Package jobs still resolve locked dependencies and build on their own platforms.

Windows additionally runs the native I/O suites listed in
`tool/test-suites/windows.txt`. Keep that list current when adding tests for
named pipes, filesystem replacement, TLS, processes or database engines.
Android runs its compiled JVM protocol tests and pinned WebRTC logging check.
Web runs the Chrome, IndexedDB, WebCrypto, WASM, service-worker and codec tests.
Linux and Flatpak retain installed-package and sandbox smoke tests.

Publishing requires successful validation for the same commit. Build artifacts
from a failed validation run are not a release. See the
[audit report](../docs/TEST_SUITE_AUDIT.md) for counts, measurements and remaining
device-testing gaps.
