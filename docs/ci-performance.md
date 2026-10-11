# CI timings

Record elapsed job and step times from GitHub Actions, not guesses based on
artifact size. Job totals exclude queue time. Linux's AppImage smoke job runs
after Debian packaging; Flatpak runs after release publication.

## Baseline: build 127

Commit `ca2aff4`, 2026-10-11. Native tests used one worker.

| Job | Total | Test step | Build step |
| --- | ---: | ---: | ---: |
| Windows | 17 min 7 s | 6 min 16 s | 5 min 28 s |
| Android | 14 min 46 s | 3 min 42 s | 8 min 25 s |
| Debian/AppImage | 12 min 31 s | Combined with build | 8 min 50 s including checks |
| Arch | 9 min 21 s | Combined with build | 7 min including checks |
| AppImage smoke | 1 min | Launch checks | Not applicable |
| Web PWA | 4 min 37 s | Combined validation and browser checks | Combined |
| Flatpak | 2 min 54 s | Sandbox launch checks | Included |

Source runs: [Windows](https://github.com/VosjeCleo/SeND/actions/runs/38143364392),
[Android](https://github.com/VosjeCleo/SeND/actions/runs/38143364466),
[Linux](https://github.com/VosjeCleo/SeND/actions/runs/38143364473),
[Web](https://github.com/VosjeCleo/SeND/actions/runs/38143364541) and
[Flatpak](https://github.com/VosjeCleo/SeND/actions/runs/38144626113).

## Cleanup changes

- Split the large widget suite by feature and move shared fixtures into
  `test/support/`. Existing test bodies and assertions are retained.
- Run native tests with two workers. No test selection or platform checks are
  removed; Windows installer and Linux launch checks still gate publication.
- Add dependency-cache fallback keys restricted to the same platform, Flutter
  archive and Rust toolchain. Package resolution still uses the current lockfile.
  Native crypto-build caches retain their exact dependency keys.

## Local comparison for build 128

On the i5-8250U laptop, 2026-10-11, both full runs passed the same 636 tests
with four skips. Times include Flutter startup and are shell-reported wall time.

| Workers | Elapsed |
| --- | ---: |
| One | 8 min 5.78 s |
| Two | 4 min 11.63 s |

Two workers reduced elapsed time by about 48%. The runs were consecutive on a
normal desktop session, not an isolated benchmark. The two-worker run followed
the one-worker run; filesystem caches and host activity may affect the result.

## Build 128 CI

Results pending. Record job and test-step times after the runs finish. Hosted
CPU, network, dependency downloads and cache state vary; one comparison does
not establish a sustained improvement.
