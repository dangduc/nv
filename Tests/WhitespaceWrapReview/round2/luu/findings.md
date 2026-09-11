# Round 2: mixed-source performance

This review uses a perspective inspired by Dan Luu. It does not represent his review or endorsement.

Reviewed head: `072a6bc0f54a52603f8cedfbcacc17d0ab836a36`.
The runner checks the frozen candidate binary SHA-256: `be02dd1fe33a39c74b8961441be55f4f91378d46935bdba99fd610d405c3e09b`.
Environment: macOS 26.5.2 (25F84), Xcode 26.6 (17F113), Intel apps under Rosetta.

## P3: mixed paragraphs retain a slow resize path with a measured increase

The candidate adds approximately 10% to synchronous visible-resize work in the tested many-paragraph note.
The native baseline already has substantial resize latency in this fixture.
This result persists when the app execution order reverses.

The fixture repeats `alpha\tbeta   Việt 👩🏽‍💻 中文   \n` 1,024 times, then appends 200 ordinary spaces.
Its initial length is 32,968 UTF-16 units. It uses Plain Text syntax and Menlo 12.
Each trial sends 64 native Space or `k` key events.
After every eighth event, the probe changes the window width and calls `displayIfNeeded`.
The actual text-container width alternates between 504 and 844 points.
The timed phase does not explicitly force complete document layout.

| Median across six trials | Native baseline | Candidate |
| --- | ---: | ---: |
| Total for eight resize requests | 2,538.11 ms | 2,800.50 ms |
| Mean request cost from those totals | 317.26 ms | 350.06 ms |
| Main-thread CPU during each trial | 2,841.81 ms | 3,097.57 ms |
| Dispatch total for 64 keys | 234.61 ms | 248.96 ms |

The two app orders each contain three trials.
The final wide layout contains 1,026 lines in the baseline and 1,027 lines in the candidate.
That one-line difference does not explain the full increase.
The probe does not attribute the increase to a specific AppKit method or new production line.

The source size and paragraph count make this a low-priority performance finding.
The larger baseline latency also needs separate attribution before a targeted correction.
Retain this fixture and document the measured increase during the review disposition.
Do not describe the whitespace correction as a general improvement to all resize paths.

## Other results

The second fixture omits the newline from the repeated unit.
Its initial length is 31,944 UTF-16 units, with one long mixed paragraph and 200 trailing spaces.
The candidate improves median resize work for this case: 318.80 ms versus 332.16 ms across eight requests.
Its key-dispatch total is 210.07 ms versus 200.58 ms for 64 events.
These small dispatch differences do not establish a separate actionable regression.

Each copied app passes 826 checks per run.
The two app orders therefore cover 1,536 native key events and 192 visible-resize requests across four app runs.
Every event checks the exact live source, committed note source, and logical caret.
Each resize checks the source and caret again.

The actual candidate getter runs 400 times in each process.
All calls reuse one immutable 96-byte paragraph-style object.
The observer forwards the original getter result unchanged and records no calls outside the main thread.
This verifies the final shared-style optimization during real edits, beyond the earlier extracted-getter probe.

## Reproduction and limits

Run `python3 Tests/WhitespaceWrapReview/round2/luu/run.py` for the native-first order.
Run `python3 Tests/WhitespaceWrapReview/round2/luu/run.py --candidate-first` for the reverse order.

The runner uses isolated app copies, disposable notes, unique preference domains, and the shared GUI lock.
`results.json` contains the native-first measurements.
`results-candidate-first.json` contains the reverse-order measurements and final line counts.
Generated code, build products, and complete logs remain under ignored `build/WhitespaceWrapReview/round2/luu`.
The recorded check count precedes the final successful evidence-write check.

The timings measure synchronous window work, rather than every displayed frame or physical live-resize event.
Final complete-layout line counts are collected after the timed phase in the reverse-order run.
Main-thread CPU includes probe logging, assertions, and deferred work.
The test does not measure macOS 13, physical held-key frame timing, every font, or all script combinations.
