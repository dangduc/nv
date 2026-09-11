# Wrapped separator review

PR: https://github.com/dangduc/nv/pull/30

The requested review has three rounds with six independent engineering perspectives.
The named perspectives describe review methods, not reviews by the named people.
Each reviewer writes and runs code to support the analysis.
Findings are posted on the PR and corrected before the next round.

| Round | Reviewed commit | Status |
| --- | --- | --- |
| 1 | `9e6c8dd6adc058e7044f2c562532af97dd4e63d4` | Six reviews complete; no actionable findings |
| 2 | `2ea92180939a3e51df8fe867ad548140ed455868` | Six reviews complete; P3 addressed in `e022109` |
| 3 | `e022109eaf2bad6583512c2ed2b48561d9dae011` | Six reviews complete; P3 resolution verified; no new actionable findings |

The six perspectives are John Ousterhout, Dan Luu, Linus Torvalds, Kyle Kingsbury, contrarian UX, and contrarian platform compatibility.
The review scope includes single-space wrap geometry, preserved source characters, Unicode, native edits, shared layouts, performance, and deployment compatibility.

All eighteen code-writing reviews are complete.
The round-two ASCII performance finding was corrected and validated before round three began.
The Ousterhout reviewer implemented that correction and identified round three as a self-review.
The other five round-three perspectives independently reviewed the corrected production code.
No actionable finding remains unaddressed.

The implementation keeps repeated spaces and indentation literal, as recommended in the feasibility investigation.
Spaces that form a composed character with a combining mark also retain their existing behavior.
The broader rule that collapses entire space runs is outside this implementation.

The implementation-stage invalidation research is separate from these review rounds.
It tested native AppKit with an instrumented classifier and found no need for another invalidation hook.
It does not establish behavior on macOS 13.7.8.

[Round 1 PR comment](https://github.com/dangduc/nv/pull/30#issuecomment-5639941946).
[Round 2 PR comment](https://github.com/dangduc/nv/pull/30#issuecomment-5640110915).
[Round 2 correction](https://github.com/dangduc/nv/pull/30#issuecomment-5640178119).
Round-three findings and evidence are recorded in [COMMENT.md](round3/COMMENT.md) and the linked PR discussion.
