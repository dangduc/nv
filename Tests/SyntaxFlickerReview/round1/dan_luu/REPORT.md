# Round 1: Dan Luu-inspired performance review

This review uses a measurement-focused perspective inspired by Dan Luu. It does not imply his participation or endorsement.

## Result

No confirmed actionable defect in the flicker fix. The probe exercised the current production highlighter and pinned JSON grammar.

In each typing burst, the highlighter preserved provisional display data without adding or removing capture attributes. The existing debounce combined 120 edits into one parser request after typing stopped. The display-operation limit still applied across all attached layout managers.

## Executable evidence

Run from the repository root:

```sh
python3 Tests/SyntaxFlickerReview/run-parser-probe.py \
  --probe Tests/SyntaxFlickerReview/round1/dan_luu/probe.m
```

The successful run is in [output.txt](output.txt). The probe compiled as Intel Objective-C on macOS 26.5.2 with Xcode 26.6. It used native `NSTextStorage` and `NSLayoutManager`, without launching a browser window.

The fixture contained a 300-character JSON string and 100 additional properties. Each burst inserted 120 characters at separate positions inside the string. An 8 ms run-loop interval followed each edit. The final source length was 1,511 UTF-16 units.

| Observation | One layout | Four layouts |
| --- | ---: | ---: |
| Total burst elapsed time | 1,185.928 ms | 1,170.669 ms |
| Total synchronous storage-edit time | 20.464 ms | 30.626 ms |
| Maximum synchronous storage-edit time | 0.417 ms | 0.776 ms |
| Parser requests during the burst | 0 | 0 |
| Capture additions/removals during the burst | 0/0 | 0/0 |
| Parser requests after the burst | 1 | 1 |
| Capture additions/removals when the result arrived | 303/1 | 1,212/4 |

The timer surrounds only `replaceCharactersInRange:withString:`. These measurements do not represent input-to-display latency, drawing time, or a comparison with the previous implementation.

Every edit invalidated semantic captures while preserving display permission in each existing layout. New characters had no provisional capture. All source characters survived the display update.

## Fragmentation and budget checks

The probe counted adjacent runs with different capture values. Each layout started with 202 colored runs and 405 total runs. After 120 insertions, these counts were 322 and 645. The replacement parse restored 202 and 405. Each insertion introduced at most one colored run and two total runs in this fixture.

An additional test supplied capture arrays directly to the production display method. This isolates the display limit from parsing:

- One layout accepted 4,096 capture writes. It rejected 4,097 captures with zero partial writes.
- Four layouts accepted 1,024 captures each, for 4,096 writes. They rejected 1,025 captures each with zero partial writes.
- Rejection removed previous captures and display permission in every layout.
- Closing the highlighter removed retained captures and display permission.

The executable passed 12,192 assertions. Most assertions validate range traversal. The behavioral scope is two 120-edit bursts and four display-budget boundary cases.

## Fixture corrections and limits

[initial-output.txt](initial-output.txt) records an incorrect assertion about raw `effectiveRange` segments. After parsing, adjacent equal-valued segments can remain separate: the initial run reported 202 colored segments before editing and 442 after replacement. Those segments do not establish separate visible color runs or a memory leak. The final probe explicitly combines adjacent equal values when counting color runs.

[unsupported-selector-output.txt](unsupported-selector-output.txt) records a second fixture error. `NSLayoutManager` does not implement the attempted `NSAttributedString`-style longest-range selector. The final probe uses its supported `effectiveRange` API and combines neighboring values itself.

This review does not establish a bound on TextKit's internal allocation, sustained drawing cost, or arbitrary editing histories. A useful second-round check would compare raw segment behavior against the previous clearing strategy and measure repeated bursts. The existing application limit controls explicit capture writes; it is not a claim about all TextKit work.

Markdown, HTML, IME input, a live window's drawing delegate, and cancellation during an active worker were outside this probe. No production change is requested from this round.
