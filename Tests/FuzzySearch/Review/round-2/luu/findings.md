# Round 2 responsiveness review

The round-one dense literal-highlight stall is repaired in the measured path.
One separate P2 remains: a late fuzzy position can occupy the shared search worker long enough to delay another browser's query.
This report uses a measurement-focused perspective. It does not represent Dan Luu.

Input HEAD: `deb3db3f6ea21e6158a1e449d73cac134410affb`.
The exact source hashes, compiler, commands, results, and fixture hash are in `native-results.json`.
The measured service SHA-256 is `082fa72f1732f769aacea051b6e0380b60ca207386d23a59214ce12be0befbcf`.
These inputs precede the separately planned callback-ownership repair.
Every recorded production input was verified against the stated HEAD.
The callback-ownership edits began changing the working service while this report was written; those later edits are outside these measurements.
No production code or earlier test was edited by this review. No commit was created.

## P2 — Yield the shared worker during long source-position mapping

Primary location in the measured source: `Sources/Search/NVSearchService.m:332`.
Supporting location: `NVSearchMapRanges`, lines 61–83 of that file.

Trigger: browser A displays a fuzzy result whose matching text is near the end of a large note.
Source highlighting requests positions through `NVBrowserSession.m:372–384`.
Visible fuzzy excerpts use the same service through `NVBrowserSession.m:581`.
While A's positions remain current, browser B starts another query.
Both requests run on the service's single `_worker` queue.

The position request runs native position extraction and the entire UTF-16 range-mapping pass in one queue block.
The mapper enumerates every preceding composed character and normalizes each substring before reaching a late offset.
Its cancellation checks do not yield the worker to another owner's queued search.
Starting a query for B cancels B's earlier requests, while A's current presentation request continues.

The independent fixture uses a real search service and native engine, with one immutable note titled `fixture`.
The source contains 1 MiB or 4 MiB of ASCII `x`, followed by `needle`.
Browser-owner A completes query `needle`; the fixture then requests its native source positions.
Immediately afterward, owner B submits query `q` against the same warmed corpus.
The same B query is measured before the position request, then cancelled to prevent completed-query reuse.
Both timed B requests follow the production search path.

| Source prefix | B query alone | Native positions | `NVSearchMapRanges` | B query behind positions |
| --- | ---: | ---: | ---: | ---: |
| 1 MiB | 0.103–0.107 ms | 3.478–3.514 ms | 183.212–186.655 ms | 186.798–190.287 ms |
| 4 MiB | 0.298–0.321 ms | 14.022–14.054 ms | 729.927–729.933 ms | 744.273–744.373 ms |

Each position result contains one source range, with the exact location of the final `needle`.
The 2,048-range display cap cannot limit this work: the cost comes from traversing text before that one range.
The phase timers establish that range mapping dominates this delay, rather than native position extraction or B's scoring.
The main thread remains available, but B's results cannot complete for roughly three quarters of a second in the 4 MiB case.
This is separate from the previously documented scoring and publication target misses.

Cancellation works when applied to A's actual position owner.
In the 4 MiB control, cancellation after about 20 ms stopped the mapping pass and suppressed its callback.
B completed 0.316 ms after cancellation, with a total wait of 20.594 ms.
Normal activity in B does not supply that cancellation because A's result and selection remain valid.
A remedy must let unrelated queued search work proceed during a long position-mapping request, while preserving mapping correctness and existing cancellation fences.

## Repaired literal-highlight path

The fixture invokes the unchanged production `refreshSearchHighlights` method, the real service, and the extracted production editor attribute methods.
Its editor uses native `NSTextStorage` and `NSLayoutManager` objects.
A dense 8 MiB prose source and query `a` return exactly 2,048 displayed ranges.
Three observations measured:

| Operation | Main-thread time |
| --- | ---: |
| Submit source-highlight refresh | 0.028–0.444 ms |
| Apply 2,048 native temporary highlights | 0.583–0.906 ms |
| Clear those highlights | 0.420–0.475 ms |

Submission through completed application took 40.877–49.904 ms, including worker comparison and discovery.
Assertions verify that a real temporary highlight exists, source text stays unchanged, and attributes apply on main.
These measurements resolve the round-one dense-source finding in this fixture.

A separate rare literal match at the end of an 8 MiB ASCII source took 36.216–36.963 ms to deliver.
A peer query behind it completed in 37.124–37.555 ms, versus 0.619–0.649 ms alone.
No additional actionable finding is asserted for that measured literal path.

## Reproduction and limits

Run from the repository root:

```sh
python3 Tests/FuzzySearch/Review/round-2/luu/run.py
```

Result: exit 0; 78 assertions passed across dense, literal, and position fixtures.
The runner has a 35-second timeout for each fixture process; asynchronous waits inside the fixture have a 20-second deadline.
It performs three dense observations, two rare-literal observations, two position observations at each of two sizes, and one cancellation control.
It does not sweep library sizes or query combinations.

The runner copies Objective-C production source before compilation to isolate its input from concurrent repairs.
The service copy adds clocks immediately around the unchanged native-positions and range-mapping calls.
The hash of that instrumented translation unit is also recorded.
The controller and editor methods are extracted without edits.
The service, native engine, corpus, and query classes are production implementations.
A narrow session double supplies a current title occurrence for the dense controller check.
The queued-position check calls the actual public service APIs; its browser route is established from the cited production call sites.

Measurements use arm64 `-O2`, macOS 26.5.2, and Xcode 26.6.
No Intel process, application library, personal note, or preference domain was opened.
The fixtures exclude windows, painting, glyph layout, and full AppController lifecycle behavior.
The late-position fixture is ASCII; it establishes the measured shared-queue delay and does not provide a Unicode performance bound.
These are controlled cases, not estimates of typical user-note latency.
The report makes no new claim about the known corpus-scoring or table-publication limits.
