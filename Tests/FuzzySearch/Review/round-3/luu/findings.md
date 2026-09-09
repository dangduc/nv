# Round 3 responsiveness review

No actionable finding was established in this bounded final review.
The repaired worker scheduling handles repeated arrivals from another browser owner while preserving the complete late Unicode ranges.
This review uses a measurement-focused perspective and does not represent Dan Luu.

The production service matches commit `11f571f` exactly.
The recorded runs began at HEAD `de0d194d3dc9fd4d8d09334eeb046e63f3f59cb5`.
The assigned review HEAD was `a9636d6`; the measured production service remained identical to `11f571f`.
Its service SHA-256 is `ab2cb80e9365e47ae6c82dd086022c12089aeb8da385e95e6084909f8d1a52b8`.
Each result JSON records the command, source hashes, fixture hash, compiler, and operating system.
All recorded production inputs still matched the working tree when this report was written.
No production code or previous test was edited. No commit was created by this review.

## Independent fixture

The new fixture compiles the production service, query, corpus, and native engine.
It uses one modest Unicode source: 189,022 UTF-16 units, encoded as 360,036 UTF-8 bytes.
The prefix repeats decomposed accents, an emoji modifier/ZWJ sequence, Hangul Jamo, a regional-indicator flag, and CRLF.
Two different exact phrases at the end use decomposed accents, supplementary emoji, and Hangul Jamo.
The query uses their NFC forms.

The fixture expects exactly `{189000, 8}` and `{189017, 5}`, in that order, in the original source.
It verifies the complete array, composed-character boundaries, empty title/tag ranges, and unchanged source characters.
It also verifies that the completed search still returns the same sole note UUID after position work.
This is a mapping and scheduling check, not a broad ranking test.

The first case controls arrivals with a subclass that pauses the worker **after** each unchanged production position batch returns.
The subclass does not change the production cursor, offsets, ranges, limits, or queue.
Four successive queries reuse the same peer owner, each arriving after the preceding query completes.
Each fresh query returns its correct empty result before the final position callback.
The required main-thread completion order is:

```text
q0 → q1 → q2 → q3 → positions
```

The callback asserts that all four peer completions occurred before position publication.
The ordered Unicode range array must remain intact after all those yields.
This extends the earlier one-peer ASCII measurement with non-ASCII source and repeated peer arrivals.
No elapsed-time threshold decides whether scheduling passes.

Two additional observations run without gates.
In both, the ordinary peer query completes before positions, and all 20 production position batches run off main.

## Native observations

| Operation | Observed time |
| --- | ---: |
| Peer query delivery, no gates | 15.713–15.900 ms |
| Complete Unicode position delivery, no gates | 44.328–45.603 ms |
| Longest resumed production batch, no gates | 1.546–1.639 ms |
| Submit position request on main, all three cases | 0.008–0.012 ms |
| Apply both late ranges through native TextKit on main | 0.112–0.181 ms |
| Clear those temporary highlights on main | 0.002 ms |

The first batch includes native position extraction; its observed total was about 15 ms.
That call's uninterruptible nature remains documented and is not a new finding.
Timing excludes the deliberate gate waits from each batch duration.
The gated case's total delivery time is not used as a responsiveness measurement.

The native TextKit check extracts the unchanged production `setSearchHighlightRanges:` and `removeHighlightedTerms` methods.
Real `NSTextStorage` and `NSLayoutManager` objects receive both expected highlights.
Assertions verify their temporary attributes and source preservation.
The checked submission and display calls showed no main-thread work regression in this fixture.

## Commands and results

Run from the repository root:

```sh
python3 Tests/FuzzySearch/Review/round-3/luu/run.py
python3 Tests/FuzzySearch/Review/round-3/luu/run.py --sanitize
python3 Tests/FuzzySearch/Review/round-3/luu/run.py --mutation no-yield
```

The native and AddressSanitizer/UndefinedBehaviorSanitizer runs each passed 82 checks, with exit 0 and no sanitizer diagnostics.
The negative control removes both batch limits in a generated service copy.
It exited 1 at the expected assertion:

```text
mapping publishes after four separately queued peer completions
```

This demonstrates that the ordering fixture rejects the original queue-blocking behavior.
The normal compiled service is byte-identical to production; only the negative-control copy changes the limits.
Raw evidence is in `native-results.json`, `sanitize-results.json`, and `native-no-yield-results.json`.

## Limits

The runs use arm64 code on macOS 26.5.2 with Xcode 26.6.
Native timings use `-O2`; sanitizer timings are validation evidence, not latency estimates.
Each process has a 25-second timeout, each asynchronous wait has a 10-second deadline, and each deliberate worker gate has a five-second guard.
The review uses one Unicode source size, one controlled four-arrival sequence, and two ungated observations.
It does not establish a hard latency bound, typical-user latency, sustained-load fairness, or behavior for unusually long composed sequences.

No Intel process, real application library, personal note, or preference domain was opened.
The TextKit fixture has no window, text container, glyph layout, or painting.
It does not exercise complete AppController lifecycle or large-corpus result publication.
The known native-extraction and 150 ms corpus-scoring limits remain outside this finding set.
