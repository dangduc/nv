# Round 1 performance review

Reviewed HEAD `c7e61cbd5cd863cc285d09614b4cd3a2b18e11e7` against base `a9539cc`.
The final executable runs saw current HEAD `e4d3ac4cd3050b6c2b27cc9f074d666aba6625a1`, which adds the other review records.
Every measured production file was hash-checked against the assigned `c7e61cb` tree and was identical.
The review used a measurement-focused lens. It does not represent Dan Luu.
Production source hashes and the native toolchain are recorded in `source-record.json` and `browser-source-record.json`.
This review changed no production file or original test and created no commit.

## P2 — Bound literal source highlighting on the main thread

Primary location: `Sources/Browser/AppController_Search.m:168`.
Supporting code: `Sources/Search/NVSearchQuery.m:43–57`, `Sources/Editor/LinkingEditor.m:464–478`.

Trigger: Fuzzy mode, search highlighting enabled, query `a`, and a selected title-match occurrence whose committed source contains many literal matches.
A long imported source or pasted log can reach the 8 MiB size already used by this feature's cancellation fixtures.
The controlled reproduction repeats the sentence `meeting notes: a clear goal and a small task to finish today.` with newlines.
Its 8 MiB source produces 1,082,400 disjoint literal ranges.

The new title-row branch scans the complete source and applies every range synchronously.
The fixture executes the unchanged production `refreshSearchHighlights`, `literalRangesInString:`, `setSearchHighlightRanges:`, and `removeHighlightedTerms` methods.
It uses a real `NSTextStorage` and `NSLayoutManager`, and asserts execution on the main thread.
With a newly created layout manager, the first refresh takes 739–755 ms.
Rebuilding existing highlights takes 965–994 ms.
Removing those attributes alone takes over 200 ms.
The removal also runs from the pending-result callback at `AppController_Search.m:63`, so a subsequent query can stall before background search starts.

These costs are outside the documented native scoring and service benchmarks.
The known unmet 150 ms native search goal is not a new finding here.
The problem is that the UI cannot process input or cancellation while this separate synchronous work runs.
Literal range calculation and attribute application/clearing need a bounded, cancellation-aware presentation path.
Preserve literal highlight semantics while limiting each main-thread operation.

Reproduce from the repository root:

```sh
python3 Tests/FuzzySearch/Review/round-1/luu/run.py 8388608
```

Result: exit 0; production-method, source-preservation, and native temporary-attribute assertions pass.
`highlights.csv` records three observations per size and query.
`refresh_ms` starts with existing highlights. `fresh_refresh_ms` uses a newly constructed native editor storage and layout manager, with no earlier highlight attributes or range fragmentation.
`range_scan_ms` and `apply_ms` measure the component calls; they are separate observations and must not be added to `refresh_ms`.

| Source | Literal ranges for `a` | Fresh layout refresh | Existing-highlight refresh | Clear highlights |
| --- | ---: | ---: | ---: | ---: |
| 16 KiB | 2,113 | 1.556–2.212 ms | 2.843–4.593 ms | 0.620–1.000 ms |
| 1 MiB | 135,300 | 87.246–88.214 ms | 115.879–120.605 ms | 27.307–27.693 ms |
| 4 MiB | 541,200 | 363.881–369.210 ms | 468.361–486.151 ms | 110.715–113.144 ms |
| 8 MiB | 1,082,400 | 739.447–754.768 ms | 965.236–994.469 ms | 226.119–229.527 ms |

## Publication, capture, and request checks

Reproduce:

```sh
python3 Tests/FuzzySearch/Review/round-1/luu/run-browser.py
```

Result: exit 0; occurrence publication, snapshot invalidation, and request-identity checks pass.
The executable compiles the complete production browser session and search implementation.
Publication uses precomputed results and a service gate, which excludes native scoring from its timer.
The coordinator capture methods and the data-source fill method are extracted unchanged.
UUIDs come from `CFUUIDCreate`; the fixture does not use the documented zero-prefix UUID pattern.

For 10,000 notes, the final recorded run measured:

| Operation | Result |
| --- | ---: |
| Capture all committed snapshots, approximately 50 MiB source | 10.167 ms |
| Capture and install one changed snapshot | 0.064–0.207 ms |
| Repeat a notification with identical source | 0.020 ms |
| Publish 10,000 fuzzy occurrences | 12.248–12.643 ms |
| Publish 20,000 occurrences with complete title/fuzzy overlap | 34.903–37.660 ms |
| Resolve all 20,000 occurrence keys | 1.369–1.479 ms |
| Redisplay those 20,000 occurrences without rescoring | 34.781–39.027 ms |

Publication read no note bodies. Every occurrence key resolved to its unique row.
Repeating the same query 100 times and refreshing display state created no additional search requests.
Changed capture invalidated once; identical capture preserved the existing snapshot.
These measurements do not support another actionable finding in the tested paths.
Raw observations are in `browser.csv`.

## Limits

The fixtures ran as arm64 code at `-O2` on macOS 26.5.2 with Xcode 26.6.
They did not launch Intel code, open a real notes library, or change application preferences.
The highlight fixture uses native TextKit temporary attributes but has no text container, glyph layout, window, or painting.
The browser fixture excludes real AppController delegate work and table painting.
Its coordinator invalidation callback records the call; it does not model every browser's downstream refresh cost.
The highlight fixture measures those native highlight methods independently.

The selected title-row behavior is supplied by a narrow session double.
The production controller method chooses its title branch and performs the full scan/application itself.
Assertions verify the first and last returned ranges receive actual native temporary attributes, removal clears them, and source characters stay unchanged.
The synthetic sources expose scaling; they do not estimate typical user-note latency.
No claim is made about native scorer cancellation, position mapping speed, Intel performance, or full-app frame times.
