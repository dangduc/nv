Round 1 of 3 — Linus Torvalds-inspired review of correctness, bounds, and lifetime. This is an analytical perspective, not an endorsement by Linus Torvalds.

**No actionable finding in the revised fix.** The deferred cleanup respects the character-edit boundary. Its cancellation targets one selector on one editor. The existing subtraction-based range validation remains intact.

I wrote and ran an independent AppKit probe. It extracts the current `invalidateSearchHighlights`, `removeHighlightedTerms`, and `setSearchHighlightRanges:` methods. An `NSObject` adapter supplies editor ownership. `NSTextStorage`, `NSLayoutManager`, edit notifications, delayed selectors, and run-loop execution are real.

The candidate passed 51,060 assertions. Most assertions compare two attributes at each character position across 200 deterministic range trials. This count does not represent 51,060 independent scenarios.

- The range model checks valid overlaps, zero-length ranges, out-of-bounds ranges, `NSNotFound`, and unsigned overflow. An independent per-character oracle checks the resulting background union. Cleanup preserves unrelated temporary metadata and source contents.
- Six empty and Unicode fixtures delete composed characters through `NSTextStorage`. They include emoji, a joined emoji sequence, combining accents, CRLF, and paragraph separators. All callbacks clear backgrounds without editing-time layout mutation.
- Fresh results survive an older queued cleanup. Cancellation leaves another editor's cleanup and an unrelated selector intact.
- A completion during nested character editing installs no ranges. Neither the initial call nor nested run-loop retries mutate layout during the active edit. Cleanup completes after the outer `endEditing`.
- Detaching storage accepts pending cleanup without a range exception. A queued selector releases its retained receiver after completion. Cancelling a selector does not retain its receiver indefinitely.

Three sensitivity controls failed as expected:

| Deliberate defect | Evidence |
| --- | --- |
| Remove pending-selector cancellation | 23,302 assertions fail because old cleanup erases current highlights. |
| Remove the character-edit guard | Three assertions detect premature range installation and layout mutation. |
| Use addition-based bounds arithmetic | A hostile range raises `NSRangeException` in AppKit's temporary-attribute storage. |

Run `python3 Tests/SourceBackspaceReview/round1/torvalds/run.py`. The probe compiles as Intel code and runs through Rosetta on macOS 26.5.2. See [the probe](probe.m.in), [candidate output](candidate-output.txt), and [manifest](manifest.json). Each control has its own output file. Compilation produced no warnings. SHA-256 hashes for all four production files matched before and after the run.

The revised cleanup retries after 10 ms if character editing remains open. This review tested that revision, after the earlier review identified zero-delay retry churn. The probe does not establish a latency bound.

Limits: this is a method-level test. It does not create a browser or paint a window. The actual `AppController` attachment path, drawing delegate, and input method are outside this probe. The reported macOS 13 crash was not rerun on this macOS 26 host. I changed no production files.
