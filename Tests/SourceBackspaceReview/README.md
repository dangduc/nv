# Source backspace review

This record covers [PR #21](https://github.com/dangduc/nv/pull/21).
The six requested perspectives use separate agent reviews with executable evidence.
The named perspectives do not imply participation or endorsement by those people.

## Findings and corrections

The first performance review found repeated zero-delay callbacks during an open character edit.
A separate agent changed retries to 10 ms while preserving immediate display suppression and callback cancellation.
The [correction probe](fixes/retry/report.md) checks the delay, eventual cleanup, and fresh-result cancellation.
The zero-delay negative control fails its intended assertion.

## Review rounds

Each report identifies the tested production hashes, its commands, results, and limits.
Assertion counts include repeated matrix positions; they are not counts of distinct user workflows.
The first ownership, performance, and state reviews tested the initial candidate before the retry correction.
The remaining first-round reviews tested the corrected implementation in `c2209e2`.
Later commits record review evidence without changing production code.

| Round | Perspective | Evidence | Result |
| --- | --- | --- | --- |
| 1 | John Ousterhout | [Ownership and interfaces](round1/ousterhout/report.md) | No finding; 23 checks. |
| 1 | Dan Luu | [Performance](round1/luu/report.md) | Retry churn; corrected. 8,216 checks. |
| 1 | Linus Torvalds | [Correctness and lifetime](round1/torvalds/report.md) | No finding; 51,060 assertions. |
| 1 | Kyle Kingsbury | [State and interleavings](round1/kingsbury/report.md) | No candidate finding; 13 checks and two rejected controls. |
| 1 | Contrarian A | [Complexity and causal evidence](round1/contrarian-a/report.md) | No finding; 16 checks and five rejected simplifications. |
| 1 | Contrarian B | [Visual behavior](round1/contrarian-b/report.md) | No finding; 7,680 combinations and 39,819 assertions. |

Rounds two and three are in progress.

## Application validation

The unsigned Intel Development build succeeds on macOS 26.5.2 with Xcode 26.6.
The [maintained copied-app suite](../SourceBackspace/README.md) passes 310 checks.
The original app reproduces the first-deletion range exception at index 25 with a string length of 25.
The fixture installs actual search backgrounds and caches native layout before deletion.
It supplies that precondition directly; it does not exercise search-field input.

The multiple-window suite passes its 35 main checks, then crashes after 11 relaunch checks during library replacement.
The [baseline comparison](round1/kingsbury/report.md) reproduces that later crash in the old app.
The harness suppresses only the old premature cleanup to reach that stage.
It does not change the library-switch path.

The aggregate regression stops at the fuzzy-browser focus precondition.
The focused highlight checks run separately and pass.
HighlightBounds passes 134 checks each in native, Intel, and native ASan/UBSan runs; all 11 mutation controls fail as expected.
The shared-source observer probe passes seven checks in each of its native and Intel sanitizer runs.

The reported macOS 13.7.8 environment remains untested.
Method adapters validate native storage and callback behavior, but do not establish browser behavior or rendered pixels unless their reports state otherwise.
