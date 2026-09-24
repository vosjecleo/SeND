# Image-heavy scrolling investigation — build 99

> Historical record: observations, plans and validation below apply to the named
> build/date. For the current 0.9.34+106 milestone, see the [documentation index](README.md)
> and [1.0 hardening checklist](RELEASE_READINESS.md). Open validation items are
> not automatically resolved by a later release.

Scope: source inspection, not a device performance trace. No scroll controller,
sliver anchoring, pagination thresholds, or gesture logic was changed for this
investigation. Confidence below concerns likely mechanisms, not a claimed
reproduction of every reported lockup.

| Evidence | Likely effect | Confidence / next step |
| --- | --- | --- |
| `mobile_media.dart`: `_MobileImage._learnDimensions` asynchronously replaces metadata dimensions and rebuilds the frame. Missing/wrong metadata initially uses a different fallback size. | Row extents change while scrolling through newly decoded images. | High. Profile layout invalidations; retain a stable measured aspect-ratio cache by media identity before altering anchor code. |
| `matrix_event_mapping.dart`: `_mappedMessages` maps all retained events whenever messages are read; `_timelineWindowEvents` returns the full loaded timeline. | More history increases synchronous mapping work on rebuilds. | High mechanism, medium contribution. Measure CPU samples and map counts, then memoize by event revision rather than adding scroll-window truncation. |
| `matrix_timeline_support.dart`: metadata hydration rescans the loaded timeline; sender-profile refresh is requested per message before unique-sender filtering. | Repeated asynchronous work and notifications during sync bursts. | Medium. Measure deduplication hit rate and rebuild count; coalesce metadata notifications and process changed event/sender IDs. |
| `LifecycleMemoryImage` owns one codec per visible animation and advances with timers, independently of UI ticker state. | Several large animated images can consume decoding/raster time together. | Medium. Capture frame timings on Android; consider visibility-gated decoding without changing scroll offsets or disabling intended GIF playback. |
| Shared avatar/media caches and generation checks already exist. | A blanket cache reset on resume would worsen downloads and layout churn. | High. Preserve those caches; instrument misses and byte budgets before changing eviction. |

Suggested reproduction: use a test room with 100+ mixed portrait/landscape
attachments, compare cold/warm cache, fast scroll, then 3 background/resume
cycles. Record Flutter profile-mode frame timings, decoded image dimensions,
cache hit counts, and metadata notification counts. Run the same room without
animations to distinguish layout churn from codec/raster pressure. Do not log
message content, access tokens, media keys, or private URLs.
