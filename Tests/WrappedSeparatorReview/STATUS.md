# Wrapped separator review

PR: https://github.com/dangduc/nv/pull/30

The requested review has three rounds with six independent engineering perspectives.
The named perspectives describe review methods, not reviews by the named people.
Each reviewer writes and runs code to support the analysis.
Findings are posted on the PR and corrected before the next round.

| Round | Reviewed commit | Status |
| --- | --- | --- |
| 1 | `9e6c8dd6adc058e7044f2c562532af97dd4e63d4` | Six reviews complete; no actionable findings |
| 2 | Pending | Not started |
| 3 | Pending | Not started |

The six perspectives are John Ousterhout, Dan Luu, Linus Torvalds, Kyle Kingsbury, contrarian UX, and contrarian platform compatibility.
The review scope includes single-space wrap geometry, preserved source characters, Unicode, native edits, shared layouts, performance, and deployment compatibility.

The implementation keeps repeated spaces and indentation literal, as recommended in the feasibility investigation.
Spaces that form a composed character with a combining mark also retain their existing behavior.
The broader rule that collapses entire space runs is outside this implementation.

The implementation-stage invalidation research is separate from these review rounds.
It tested native AppKit with an instrumented classifier and found no need for another invalidation hook.
It does not establish behavior on macOS 13.7.8.
