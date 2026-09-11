# Word-wrapping review

Base: `b6a5696` (upstream master).

The review uses engineering perspectives inspired by the requested reviewers.
The named people did not conduct or endorse these reviews.
Each round uses six independent code-writing reviewers.
Findings and corrections are published as PR comments before the next round.

| Round | Reviewed commit | Status |
| --- | --- | --- |
| 1 | `4b04970` | Complete; cache correction applied |
| 2 | `4c8f6b4` | Complete; no new revisions required |
| 3 | Pending | Pending |

## Initial validation

The Intel Development build passed on macOS 26.5.2 (25F84), Xcode 26.6 (17F113).
The standalone suites passed on arm64 and x86_64 through Rosetta.
Each architecture passed 74,214 checks and rejected the previous character-wrapping behavior in the negative control.
The copied-app suite passed 1,305 checks.
The existing space-wrapping app suite also passed all 843 checks.
The required multiwindow runner passed 35 primary checks and restored-window checks, then crashed during library replacement (exit 245).
The required aggregate runner passed through the new suites, then failed the Fuzzy UI active-browser assertion.
Both failure signatures match the recorded [regression baseline](../TypingPerformance/VALIDATION.md#regression-baseline).
These runners did not pass. Later aggregate entries did not run in this invocation.

The test host does not establish runtime compatibility with macOS 13.7.8.
The app screenshot uses native view drawing with disposable notes.
It does not test the final display compositor.

## Round-one resolution

[All six findings](https://github.com/dangduc/nv/pull/28#issuecomment-5631862180) are posted on PR 28.
The typesetter now releases completed paragraph analysis in `endParagraph`.
Defensive cleanup remains in `beginParagraph` and `dealloc`.
The new lifetime suite passed 144 checks on both architectures.
The exact previous implementation failed the completed-paragraph release assertion, as expected.

The long-paragraph performance finding remains a measured limitation, documented in the architecture and test guide.
The [caret-offset experiment](experiments/one-line-measurement.md) was rejected after geometry differences and slower measurements.
The unsupported paragraph-style combinations are documented with their source-app reachability limits.
Further optimization requires evidence that it preserves native layout semantics.

The [round-one resolution comment](https://github.com/dangduc/nv/pull/28#issuecomment-5631903465) identifies the corrected commit.
The corrected Intel Development build passed.

The corrected build passed 74,358 standalone checks per architecture, 1,305 copied-app word checks, and 843 prior space checks.
Its executable SHA-256 is `62c09640835e03f1fcf5bb559565f220801685c0f5241187f078943cf6fc5f8e`.
The required runners repeated the same library-replacement crash and Fuzzy UI activation failure after the correction.
Their individual exit codes were 245 and 1. The prior space suite exited 0.

## Round-two resolution

All six reviewers wrote and ran new evidence against `4c8f6b4`.
No new actionable finding was identified. No further production correction was required before round three.
The cache correction preserved geometry, source histories, native selection, and measurement creation counts in the tested cases.
ASan and UBSan checks passed on both architectures.
The [round-two reports](round2/) record each probe, result, negative control, and coverage limit.
