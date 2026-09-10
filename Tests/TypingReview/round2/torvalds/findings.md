# Round 2: implementation and resource correctness

Reviewed PR #24 at `5eda58bd50bdda6b31ea705ad1ce6b256ffd671a`, against `8dde5e8`.
Read `AGENTS.md`, the architecture guidance, and the affected production code.
This review tested the new ordered link-run merge. No production files were changed.

No confirmed defect was found in this scope.

## Executed evidence

```sh
python3 Tests/TypingReview/round2/torvalds/run.py
```

The runner extracts the complete `sourceAnalysis:didFinish:` method directly from `NVNoteEditingSession.m`.
It also extracts the production link-current state functions from `NVSourceAnalysis.m`.
The fixture supplies session fields and a plain-syntax note. Both actual and oracle storage use native `NSTextStorage`.
The oracle removes every link attribute and installs the new runs, without using the production merge.

Environment: macOS 26.5.2, Xcode 26.6 (17F113), Intel target, manual reference counting, AddressSanitizer and UndefinedBehaviorSanitizer.

Production result: **12,006 cases and 598,715 checks passed**, exit 0, with no sanitizer diagnostic.

| Coverage | Result |
| --- | --- |
| 12,000 deterministic generated Unicode cases | Every resulting link range and target matched full replacement. Characters and unrelated application attributes were preserved. |
| 3,906 native character replacements | Publication handled the old ranges inherited and transformed by `NSTextStorage`. |
| Explicit overlap, split, merge, empty storage, one-character removal, and first/last UTF-16 boundaries | Every case matched the oracle. Unicode input includes surrogate pairs, combining marks, CJK, joined emoji, and CRLF. |
| 12,006 repeated canonical publications | No storage edit notifications; results stayed equal to the oracle. |
| Obsolete generation, changed syntax, and closed-session results | Each result preserved the accepted attributes without storage edit notifications. |
| Negative control: remove old runs after adding new runs | Failed on case 1, where one new run overlaps two old runs. This verifies sensitivity to publication ordering. |

Saved evidence: `output.txt` and `results.json` beside this report.
Extracted source, compile logs, binaries, and detailed outputs are under `build/TypingReview/round2/torvalds`.
The extracted publication method SHA-256 is `3779686cde48078e2ba13d52c1d33007126b5ad0734a1581dd7d778b5b84d976`.

## Code conclusions and limits

`NVNoteEditingSession.m:225-243` advances at least one index per merge iteration.
Its comparison work is linear in the number of old and new runs, with linear temporary storage.
`NVSourceAnalysis.m:21-25` creates source-ordered, non-overlapping runs through attributed-string enumeration.
The generated inputs use the same enumeration contract.

`NVNoteEditingSession.m:244-253` completes removals before additions.
The differential cases and negative control verify why overlapping old and new ranges require that order.
This review does not measure the cost of native attribute mutation, glyph layout, or font fallback.

The initial harness compared every native attribute through whole-string equality.
That assertion also compared Cocoa-created font fallback state, which can differ between batched changes and sequential oracle writes.
The final harness explicitly compares all link ranges and targets, source characters, and the unrelated application attribute placed across the source.
It does not assert equivalence of framework-generated font state.

This is a headless method test. It does not launch nvALT, attach layout managers, exercise the in-progress-edit retry branch, or retest parser semantics and worker lifetime from round 1.
The generated UTF-16 edits include arbitrary in-bounds ranges, a broader set than normal composed-character editing.
Malformed or overlapping new-run arrays are outside the production extractor's contract.
AddressSanitizer and UndefinedBehaviorSanitizer cover the compiled code, not system framework internals; leak detection is disabled.
