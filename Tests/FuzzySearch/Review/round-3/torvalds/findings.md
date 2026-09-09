# Round 3: resumable mapping and native output ownership

No actionable finding emerged from this focused review. Severity: none.
The new fixture passed 93 checks in native arm64 and ASan/UBSan runs, with no sanitizer diagnostic.

This review uses a correctness and resource-lifetime lens inspired by Linus Torvalds.
It does not represent his identity, review, or endorsement.

## Source record

The final runs started at `de0d194d3dc9fd4d8d09334eeb046e63f3f59cb5`.
The service exactly matches mapping checkpoint `11f571f`.
Its SHA-256 is `ab2cb80e9365e47ae6c82dd086022c12089aeb8da385e95e6084909f8d1a52b8`.
All recorded input hashes remained unchanged during compilation and execution.

The runner copies the complete production service into its build directory before compilation.
The probe includes that unchanged copy to access the internal cursor and batch primitive.
It links the complete production query, corpus, native bridge, and vendored matcher files.
It substitutes no service implementation, engine call, callback, or clock.
The source records also cover local headers, native includes, and Unicode data.

| Command | Result | Record |
| --- | --- | --- |
| `python3 Tests/FuzzySearch/Review/round-3/torvalds/run.py` | 93 checks passed. | [Native results](native-results.json) |
| `python3 Tests/FuzzySearch/Review/round-3/torvalds/run.py --sanitize` | 93 checks passed. No sanitizer diagnostic. | [Sanitizer results](sanitize-results.json) |

Both records contain compiler commands, exit codes, source hashes, and the path of the complete service snapshot.
The host used macOS 26.5.2 (25F84) and Xcode 26.6 (17F113).

## New evidence

- Three small cases place explicit Unicode atoms after 4,095, 4,096, and 4,097 ASCII sequences.
  Their expected NFC scalar counts and original UTF-16 lengths are constants, independent of the production normalizer and cursor.
  Every resumed cursor stops at a specified composed boundary.
  Adjacent selected sequences remain one range across batches.
- The atoms include decomposed accents, reordered combining marks, Hangul, a flag, an emoji sequence, and CRLF.
  Cancellation after the first batch returns `NVFZF_CANCELLED` without cursor advancement.
  A later invalid UTF-16 sequence returns `NVFZF_INVALID_INPUT` and clears partial ranges.
- An owned native position vector survives three interleaved search and position calls.
  Its six expected offsets also survive engine disposal until the caller frees the vector.
- Two simultaneous service position requests resume over different bodies while a third owner searches on the same serial engine.
  Both requests return their exact expected source ranges.
  The title group retains its overlapping native result, and the complete fuzzy group retains the expected native order for this corpus.
- A cancellation queued between mapping batches suppresses the position callback after the worker drains.
  A separate invalid query publishes one error and no result.
  A retained successful position object keeps its ranges and snapshot after service invalidation.

Source review covered `NVSearchMapRangesBatch`, position-work destruction, `runPositionBatch`, and the main-thread publication guard in `Sources/Search/NVSearchService.m`.
It also covered position allocation and disposal in `Sources/Search/NVFZF.c`.

## Limits

This review adds a narrow fixture instead of repeating the maintained Unicode and lifecycle suites.
It does not claim broad ranking parity, complete Unicode coverage, or a hard latency bound.
The explicit ranking expectation covers only the small service corpus in this probe.

The invalid UTF-16 case exercises the batch primitive directly.
It does not establish a normal application path that reaches mapping with an invalid prepared snapshot.
The service error case uses an invalid query, not allocation fault injection.

The runs use Foundation without an application window, editor, or live library.
They include no deliberate crash, allocation exhaustion, full-app timing measurement, or Intel execution.
No production files, maintained tests, earlier review evidence, or commits changed during this review.
