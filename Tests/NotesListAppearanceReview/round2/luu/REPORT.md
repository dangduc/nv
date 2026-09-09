# Round 2: drawing cost and redraw work

This review uses a Dan Luu-inspired measurement lens. It does not represent a review by Dan Luu.

Reviewed commit: `755bc8b849547e6714ffaa22fbb339ad65008393`.
Comparison base: `878961a`.
The production code remains unchanged since `2e3f75e794b668024cf54597110f13ccf2aff97a`.

No actionable introduced defect was found in this scope.

Round 1 measured warmed tag-cache lookups in isolation.
This round adds actual AppKit text and tag drawing to the measured work.
It also counts cache work through the production note drawing method.

## Executable evidence

Run:

```sh
python3 Tests/NotesListAppearanceReview/round2/luu/run.py --negative-controls
```

The native arm64 runner passed 610 assertions and rejected one cache-bypass mutation.

The runner extracts these exact production methods:

- Current and base `LabelsListController` tag-cache methods.
- `NoteObject` label drawing methods and `orderedLabelTitles`.
- `NSString` label parsing and `NSCharacterSet` label separators.

It also compiles the production preview attributes, rounded paths, and buffer utilities.
An `NSTextFieldCell` draws each cached title and preview into an AppKit bitmap context.
The production note drawing method draws the tag images into the same context.
Fixtures supply the notes, preferences, delegate, cell setup, and row backgrounds.

Eight assertion cases use 10, 20, 40, or 80 rows, with zero or three tags per row.
Each case draws Aqua and Dark Aqua, then performs 24 alternating appearance redraws.
Those redraws also alternate left and right tag alignment.
Every seventh row uses the selected state.

The assertions establish these properties:

- Each warm redraw performs exactly one cache lookup per visible tag.
- Warm redraws replace no cached images and add no cache entries.
- Native bitmap pixels contain drawn text, including preview body text, in both appearances.
- The representative light and dark bitmap files are written successfully.

The tag vocabulary contains 16 distinct names.
A counting dictionary records lookups and replacements during the assertion phase only.
Timed runs use ordinary `NSMutableDictionary` instances.
Bypassing the production cache lookup makes the warm-redraw image replacement assertion fail.

## Drawing measurements

Each case uses seven paired samples. Pair order alternates between the current and base implementations.
Each sample draws five times per implementation in each appearance, for ten complete bitmap draws per implementation.
Each reported sample is the mean elapsed time per complete draw.

Timing uses `CLOCK_MONOTONIC_RAW` and includes row drawing, tag lookup, image compositing, context flushing, and per-draw autorelease pool cleanup.
Cell setup, preview construction, bitmap allocation, appearance assignment, cache warmup, and PNG encoding occur outside the timed region.
Both implementations draw identical current previews and row backgrounds.
Only the tag-cache method changes between the paired runs. This isolates that part of the PR.

| Rows | Tags per row | Base median | Current median | Median paired change |
| ---: | ---: | ---: | ---: | ---: |
| 10 | 0 | 1.087 ms | 1.074 ms | -0.009 ms |
| 10 | 3 | 1.425 ms | 1.495 ms | +0.063 ms |
| 40 | 0 | 4.079 ms | 4.237 ms | +0.025 ms |
| 40 | 3 | 5.606 ms | 5.908 ms | +0.297 ms |
| 80 | 0 | 9.080 ms | 9.063 ms | -0.018 ms |
| 80 | 3 | 9.510 ms | 10.636 ms | +0.709 ms |

The paired change is the median of sample-by-sample differences, so it can differ from the difference between the two medians.
At 40 rows with three tags, base samples ranged from 5.558–5.629 ms. Current samples ranged from 5.765–5.951 ms.
The 80-row case varied more: base samples ranged from 9.199–11.192 ms, and current samples ranged from 9.759–11.931 ms.

The current tag method adds measurable cost to this drawing workload.
The 40-row case adds about 0.30 ms per draw with 120 visible tags.
The counters show proportional lookup counts without repeated raster creation after appearance warmup.
The evidence does not establish a user-visible scrolling regression or justify another appearance invalidation mechanism.
Timing has no pass threshold.

## Limits

This is an offscreen drawing fixture, not a complete table or browser window.
The active notes list is cell-based. The fixture supplies cell setup and row backgrounds rather than a complete `NotesTableView` and data source.
The fixture draws every supplied row. It does not simulate viewport culling, scrolling, event dispatch, or window compositing.
Its multiline row dimensions and setup are fixed, and its images are not application screenshots.
It does not measure full-app frame times, allocations, cold appearance latency, or large tag vocabularies.
It does not measure all PR changes together against the previous complete application.

The results describe this host and workload. They are not a guarantee for other machines or workloads.
The host's existing Intel startup stall prevented full application measurements.
No Intel application was launched for this review.
The compiler reports an existing pointer-width cast warning in `BufferUtils.c:406`.

Generated sources, compiler output, JSON samples, bitmaps, and mutation output are under `build/NotesListAppearanceReview/round2/luu/`.
