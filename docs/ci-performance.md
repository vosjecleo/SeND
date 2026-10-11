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

Commit `9160833`, 2026-10-11. All platform jobs and Flatpak passed; release
publication and the Deltie PWA/mirror update completed.

| Job | Build 127 | Build 128 | Change |
| --- | ---: | ---: | --- |
| Windows | 17 min 7 s | 15 min 1 s | 2 min 6 s faster |
| Android | 14 min 46 s | 16 min 3 s | 1 min 17 s slower |
| Debian/AppImage | 12 min 31 s | 10 min 29 s | 2 min 2 s faster |
| Arch | 9 min 21 s | 7 min 52 s | 1 min 29 s faster |
| AppImage smoke | 1 min | 58 s | 2 s faster |
| Web PWA | 4 min 37 s | 5 min 42 s | 1 min 5 s slower |
| Flatpak | 2 min 54 s | 3 min 19 s | 25 s slower |

The Windows test step fell from 376 to 249 seconds, about 34%. Android tests
fell from 222 to 168 seconds, about 24%. Their compilation steps increased from
328 to 358 seconds and from 505 to 638 seconds, respectively. Android's slower
compilation outweighed its test improvement; the cause needs further measurement.

The PWA missed the same crypto-cache key that build 127 had restored. Its log
shows a fresh Rust/WASM tool build; Flutter web compilation itself was nearly
unchanged, 49.0 versus 49.3 seconds. Android also missed the Flutter archive
cache, but restored its dependency and native crypto caches. Cache availability
must be recorded separately from code/test changes.

The longest main job fell from 17 min 7 s to 16 min 3 s, about 6%. This excludes
queue time, release assembly, transfer and Flatpak. Hosted CPU, network and
cache state vary; these two runs do not establish a sustained improvement.

Source runs: [Windows](https://github.com/VosjeCleo/SeND/actions/runs/38167781463),
[Android](https://github.com/VosjeCleo/SeND/actions/runs/38167781458),
[Linux](https://github.com/VosjeCleo/SeND/actions/runs/38167781532),
[Web](https://github.com/VosjeCleo/SeND/actions/runs/38167781414) and
[Flatpak](https://github.com/VosjeCleo/SeND/actions/runs/38169034647).
