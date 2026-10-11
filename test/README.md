# Tests

Run the native unit and widget suite from the repository root:

```sh
flutter test --concurrency=2
```

Use `--concurrency=1` when investigating order or resource contention. Test files
run independently; each test must clean up timers, platform overrides, temporary
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
- Older `build_*_test.dart` files retain regression cases from those releases.
  Add new cases to the relevant feature file where practical.

Keep shared fixtures small and deterministic. Test observable behaviour rather
than source spelling. Simulated backends do not replace device checks for RTC,
notifications, codecs, keyboards or OS permissions.

Server tests use `python -m unittest discover -s server -p 'test_*.py'` with the
server dependencies installed. Linux packaging tests use
`python -m unittest discover -s packaging/linux -p 'test_*.py'`.
The [workflows](../.github/workflows/) contain platform and browser commands;
[CI timings](../docs/ci-performance.md) records measured run times.
