# Word-wrapping review

Base: `b6a5696` (upstream master).

The review uses engineering perspectives inspired by the requested reviewers.
The named people did not conduct or endorse these reviews.
Each round uses six independent code-writing reviewers.
Findings and corrections are published as PR comments before the next round.

| Round | Reviewed commit | Status |
| --- | --- | --- |
| 1 | `4b04970` | Six reviews complete; corrections next |
| 2 | Pending | Pending |
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
