# Round 1: performance and measurement review

This review uses a Dan Luu-inspired lens. It does not represent a review by Dan Luu.

Reviewed commit: `2e3f75e794b668024cf54597110f13ccf2aff97a`.
Comparison base: `878961a`.

No actionable introduced defect was found in this scope.

The review covered tag-cache lookup cost, cache reuse across appearances, and font invalidation.
The production changes add no redraw loop, observer, or appearance-triggered cache flush.
The preview attributes retain a dynamic color instead of rebuilding each cached string after an appearance change.

## Executable evidence

Run:

```sh
python3 Tests/NotesListAppearanceReview/round1/luu/run.py --negative-controls
```

The runner extracts the exact current and base `cachedLabelImageForWord:highlighted:` methods.
Both methods run in the same native arm64 process with the production `NSBezierPath_NV` implementation.
A small preferences fixture supplies the font size. The production invalidation method runs unchanged.

The run passed 22,893 assertions:

- Thirty-two tag names and two selection states produced 96 cache entries across four named appearances.
- Eighty appearance cycles reused the original image objects without cache growth.
- Eight font changes cleared the cache and recreated images with the expected height.
- Font changes retained no prior font generations in the cache dictionary.
- The measured cache-hit batches added no image entries.

The appearances were Aqua, Dark Aqua, High Contrast Aqua, and High Contrast Dark Aqua.
Some appearances resolved to equal colors, so they shared cached images.

Two negative controls passed:

- Omitting color from the key failed the assertion for separate light and dark images.
- Bypassing cache lookup failed the assertion for reuse of the original image.

## Lookup measurements

Seven paired samples used 200,000 warmed lookups per implementation.
Each sample included light and dark drawing appearances. The pair order alternated, and autorelease pools drained every 1,000 calls.
Both implementations received identical words and selection states.

| Method | Median per 200,000 calls | Range | Median per call |
| --- | ---: | ---: | ---: |
| Base | 143.14 ms | 127.19–148.74 ms | 0.72 µs |
| Current | 702.36 ms | 655.20–756.11 ms | 3.51 µs |

The current lookup cost increased in this fixture.
Lines 120–123 of `Sources/Browser/LabelsListController.m` resolve a system color and construct an array key on each call.
The measured difference does not establish a visible scrolling regression. Timing has no pass threshold in this runner.

Repeated draws reused the same raster objects. The image-creation block at lines 124–154 runs only after a cache miss.
These results do not support adding another appearance cache or invalidation mechanism solely for this change.

## Limits

This fixture does not run the complete table, browser windows, event dispatch, or the Intel application.
It does not measure frame times, total allocations, or the application's memory use.
It does not change the user's accent color, test every system palette, or bound growth from distinct tag names.
The existing cache retains distinct names until invalidation. This change adds color variants to that existing policy.

The timing values describe this host and workload. They are not a guarantee for other machines or workloads.
The host's existing Intel startup stall prevented full application measurements.

Generated sources, compiler output, measurements, and mutation logs are under `build/NotesListAppearanceReview/round1/luu/`.
