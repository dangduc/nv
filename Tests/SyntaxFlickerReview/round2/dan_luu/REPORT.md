# Round 2: Dan Luu-inspired performance review

This review uses a measurement-focused perspective inspired by Dan Luu. It does not imply his participation or endorsement.

## Result

No confirmed actionable defect in the flicker fix. The same native edit history passed against base `8cd2c95` and fixed production revision `65e1608`.

The fix retained colors during each typing burst. The base cleared every layout after the first edit. Both implementations made identical total capture writes per burst. The fix moved removal to the replacement parse.

Raw TextKit segment counts after parsing were identical between the implementations. Their increase over the initial state also occurred with baseline clearing. The measured segment counts do not establish a leak or new fragmentation regression.

## Executable evidence

[probe.m](probe.m) links against either production implementation and uses native `NSTextStorage` and `NSLayoutManager`. It calls only their common highlighter API. Symbol lookup selects the expected pending-color behavior without changing the workload.

The fixture contains a 300-character JSON string and 100 additional properties. It starts at 1,391 UTF-16 units. Each cycle inserts 60 characters at separate positions, waits for parsing, then deletes them in reverse order. Each edit has an 8 ms run-loop interval. Deletion restores the exact initial source.

Each implementation ran six cycles with one layout and six with four layouts: 1,440 edits across 24 bursts. Both passed 75,109 assertions. Most assertions validate temporary-attribute range traversal; this count does not represent independent scenarios.

- [base-output.txt](base-output.txt): baseline clearing behavior.
- [head-output.txt](head-output.txt): fixed provisional display behavior.
- [compare.py](compare.py): extracts both pinned implementations into the ignored build directory and runs the same probe sequentially.

The reproduction script also passed in a second paired run. Its [base replay](base-replay-output.txt) and [fixed replay](head-replay-output.txt) each passed the same 75,109 assertions. Both reproduced the parser, write, and segment counts below.

Run from the repository root:

```sh
python3 Tests/SyntaxFlickerReview/round2/dan_luu/compare.py
```

The recorded runs used Intel Objective-C on macOS 26.5.2 and Xcode 26.6. They did not launch application windows.

## Display work and segments

Every burst dispatched zero parser requests during editing and exactly one after editing stopped. Both implementations made zero explicit capture writes inside `replaceCharactersInRange:withString:`.

Per completed burst and per layout:

| Operation | Base | Fixed |
| --- | ---: | ---: |
| Capture removals during the burst | 1 | 0 |
| Capture additions at replacement | 303 | 303 |
| Capture removals at replacement | 0 | 1 |

The probe checked an unchanged suffix token after every edit's run-loop interval. The base had no capture; the fixed build retained its capture. Semantic captures became obsolete immediately in both builds. All layouts agreed on distinct pending runs.

The following counts are colored segments / all segments in one layout. All four-layout runs produced the same distinct-run results.

| Phase | Base raw segments | Fixed raw segments | Base distinct runs | Fixed distinct runs |
| --- | ---: | ---: | ---: | ---: |
| Initial parse | 202 / 405 | 202 / 405 | 202 / 405 | 202 / 405 |
| Insert burst pending | 0 / 525 | 262 / 525 | 0 / 1 | 262 / 525 |
| Insert parse complete | 322 / 525 | 322 / 525 | 202 / 405 | 202 / 405 |
| Delete burst pending | 0 / 465 | 262 / 465 | 0 / 1 | 202 / 405 |
| Delete parse complete | 262 / 465 | 262 / 465 | 202 / 405 | 202 / 405 |

Raw segments come from `temporaryAttribute:atCharacterIndex:effectiveRange:`. Distinct runs combine adjacent equal capture values. The raw counts stabilized after the first cycle at the same positions. Closing the highlighter removed all colored runs.

## Synchronous edit timing

The timer surrounds only `replaceCharactersInRange:withString:`. Each row contains 720 edits. This table uses the first paired run, with no scheduling or machine-load controls.

| Layouts | Implementation | Total ms | Median ms | p95 ms | Maximum ms |
| --- | --- | ---: | ---: | ---: | ---: |
| 1 | Base | 90.096 | 0.099 | 0.304 | 1.108 |
| 1 | Fixed | 62.869 | 0.054 | 0.231 | 0.504 |
| 4 | Base | 177.339 | 0.232 | 0.490 | 2.831 |
| 4 | Fixed | 104.957 | 0.100 | 0.333 | 1.600 |

In the script replay, total edit time was 121.030 / 16.659 ms for base / fixed with one layout. With four layouts, it was 126.904 / 27.831 ms. The variation between runs limits any performance conclusion.

These samples show no synchronous edit slowdown in this workload. They do not establish a general speed improvement. They exclude deferred clearing, replacement parsing, drawing, and input-to-display latency. Total burst elapsed times include the requested run-loop intervals and are recorded separately in the logs.

## Limits

This comparison covers repeated edits at the same positions in one JSON fixture, with at most four layouts. It does not bound internal TextKit allocation, memory growth, arbitrary edit histories, or live drawing cost. It does not cover Markdown, HTML, physical IME input, or cancellation during an active parse. No production fix is requested from this round.
