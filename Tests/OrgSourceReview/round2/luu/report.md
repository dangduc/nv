# Org source review, round 2: Dan Luu perspective

This review uses a Dan Luu-inspired focus on measured costs. It does not represent his review or endorsement.
The reviewed source commit is `4dab02a9020ff8f76cceeffc75a001927255a17e`, against `f3a8abb2b7942d06ec33af64b4946cfd1b6db163`.

No new actionable finding emerged from these checks.
The Round 1 fix removes repeated line scans from the dense-link loop.
The new supplemental passes and scanner checks retain bounded behavior on the workloads below.
Large notes and long paragraphs still have material limits.

## Representative notebook and editing

The new notebook fixture contains release tasks, properties, Unicode prose, emphasis, web links, file links, nested lists, tables, and source blocks.
It also contains comments immediately after directives and hashtag prose.
Section identifiers vary across the generated notebook. This is representative synthetic content, not a sampled user corpus.

The probe imports the current production highlighter without edits.
Five fresh-parser trials per size produce these results:

| UTF-16 units | Captures | Median parse and capture time | Maximum | Fallbacks |
|---:|---:|---:|---:|---:|
| 794 | 44 | 1.895 ms | 3.147 ms | 0/5 |
| 6,016 | 338 | 5.275 ms | 5.459 ms | 0/5 |
| 23,964 | 1,346 | 16.107 ms | 16.467 ms | 0/5 |
| 95,828 | 5,378 | 63.791 ms | 74.573 ms | 0/5 |
| 287,828 | none | 122.748 ms | 123.291 ms | 5/5 |

Every trial recovers with captures for a small note on the same parser instance.
The largest fixture reaches the existing budget fallback.
The observed maximum also shows that the 120 ms deadline is cooperative, rather than an exact elapsed-time ceiling.

Twelve successive edits in the 6,016-unit notebook produce the same capture multisets as fresh parses.
The edits include missing emphasis delimiters, TODO replacement, comment-prefix changes, incomplete links, Unicode replacement, and an incomplete source-block terminator.
Their incremental times range from 3.529 to 3.821 ms on this host.
An already-cancelled request returns no captures in 0.001 ms, and subsequent analysis succeeds.
The length guard also selects plain source for 524,289 units, then recovers on a small note.

These measurements exclude event delivery, queue delay, layout, drawing, and total typing latency.

## Supplemental work and display limits

The probe also calls the unchanged `NVOrgCaptures` function directly on an already-parsed tree.
This isolates the supplemental passes from query collection and capture sorting.
Five trials show medians of 0.045, 0.356, and 1.344 ms for 794, 6,016, and 23,964 UTF-16 units.
Those passes add 11, 88, and 352 captures respectively.

The implementation allocates two temporary buffers totaling three bytes per UTF-16 unit.
The existing input guard bounds these buffers to 1.5 MiB per analysis.
This calculation excludes source snapshots, trees, capture objects, and allocator overhead.
It is not a process-memory measurement.

The display probe uses the real `applyCaptures` method and four `NSLayoutManager` instances.
Its 1,346 captures display completely across three layouts, with exactly one attribute write per capture per layout.
Adding a fourth layout causes all layouts to select plain source, with zero new capture writes.
Removing that layout restores the cached revision across the remaining three layouts.
The probe also checks that capture attributes stay out of the note storage.

The 95,828-unit fixture parses successfully but exceeds the existing 4,096-write display budget even for one layout.
Its source therefore remains plain under that policy.
This limit predates Org support. The evidence does not imply that every successfully parsed note displays colors.

## Dense paragraphs after the Round 1 fix

The independent link fixture mixes described web links, inert file links, bare web URLs, Unicode labels, and ordinary prose.
Each trial decorates the text, inserts an actual character, refreshes its range, deletes that character, and refreshes again.
All link counts, labels, destinations, and final source text match expectations.

| UTF-16 units on one line | Full refresh median | Insertion refresh median | Deletion refresh median |
|---:|---:|---:|---:|
| 13,184 | 4.639 ms | 4.860 ms | 4.857 ms |
| 52,736 | 16.400 ms | 17.361 ms | 17.573 ms |
| 210,944 | 61.827 ms | 70.221 ms | 70.891 ms |

The measured growth is consistent with a linear scan across these sizes.
This supports the fix at `Sources/Editor/AttributedPlainText.m:247` with a different workload from Round 1.
It does not remove all synchronous decoration cost.
The largest dense paragraph still requires approximately 71 ms for each refresh.

Splitting the same content into short CRLF lines reduces the largest insertion and deletion refresh medians to 0.179 and 0.177 ms.
Its full refresh still costs 62.990 ms.
The line-based edit range explains this difference. These results do not establish a frame-time guarantee for arbitrary notes.

## Scanner state cost

The scanner probe imports the patched implementation directly and uses only ordinary valid states.
It measures 200,000 encode/decode pairs at each selected depth.
It checks every restored indentation, bullet, and heading value after each batch.

| Simultaneous list and heading depth | Serialized bytes | Mean encode/decode pair |
|---:|---:|---:|
| 0 | 8 | 11.205 ns |
| 1 | 14 | 15.345 ns |
| 4 | 32 | 30.420 ns |
| 16 | 104 | 78.975 ns |
| 32 | 200 | 139.355 ns |

The cost grows with stack depth, as the validation and copy loops imply.
The numbers measure isolated callbacks, not their total contribution during parsing.
No unpatched scanner or invalid state is part of this probe.
These measurements cannot quantify the difference from the previous representation.

## Reproduction and limits

Run the independent probes:

```sh
python3 Tests/OrgSourceReview/round2/luu/run.py
```

The parser and display probe passes 42,718 checks. The link probe passes 120 check groups.
Five valid scanner states retain all values after 1,000,000 encode/decode pairs.
The source hashes, commit, host, and compiler appear in `metadata.json`.
The output files preserve every measurement.

The host runs macOS 26.5.2 and Xcode 26.6.
The probes compile Intel code for a macOS 10.13 deployment target and run through Rosetta.
Other build and review work can affect elapsed times.
There are no machine-dependent timing assertions.
These checks do not establish behavior on an actual macOS 10.13 host or complete Org semantic coverage.
