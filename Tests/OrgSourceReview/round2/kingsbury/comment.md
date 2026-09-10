## Source review round 2 — state consistency and recovery

Kyle Kingsbury-inspired review perspective, not a review by Kyle Kingsbury.

**No actionable defect found.** New executable evidence passed **42 checks** at `4dab02a9020ff8f76cceeffc75a001927255a17e`.

The native probe compiles the production parser and highlighter.
A subclass counts real results without changing them.
The production worker queue, main-thread publication, scanner codec, Org query, and supplemental pass remain active.

- A 13,190-unit note produces 2,100 captures. One layout fits the display budget, but two exceed it. Both use complete plain-display fallback. Detachment restores the cached colors without a new parse.
- A peer joins after an edit and before analysis. The original layout keeps provisional colors. The new peer receives no stale ranges. Both converge to the current result.
- Empty source and a source one unit over the length limit retire both capture tokens. Smaller source restores Org colors without a note reopen.
- Repeated attachment and recovery preserve source, persistent attributes, independent search backgrounds, and the corrected hashtag/comment distinction within the asserted ranges.

Command: `python3 Tests/OrgSourceReview/round2/kingsbury/run.py`.
Evidence: `Tests/OrgSourceReview/round2/kingsbury/{probe.m,output.txt,metadata.json,report.md}`.
The run used macOS 26.5.2, Xcode 26.6, and Intel code under Rosetta.
Input hashes remained stable during the run.

Limits: two deterministic sequences supplement round 1's obsolete-result and closure schedules.
They do not cover live browser Undo, IME composition, disk persistence, painting latency, or actual macOS 10.13 execution.
