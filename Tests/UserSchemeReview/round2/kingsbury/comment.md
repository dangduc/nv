### Review round 2 — Kyle Kingsbury-inspired correctness perspective

No actionable defect attributed to this PR. This is an engineering perspective, not actual authorship or endorsement.

Independent composition and restart evidence passed **86 checks** against corrected production `0fc7aca`. Japanese/emoji marked source survives six inherited appearance changes, three palette edits, and peer navigation with its attributes, selection, focus, model boundary, and Undo state preserved. Native text-input commit and successful checkpoints retain both notes' UUIDs, source, syntax, and tags after restart. Edited palette archives persist byte for byte; the unedited dark foreground stays registration-only.

A direct `unmarkText` variant raises a layout exception at index 43, length 37. A bounded control with every in-composition palette and appearance change disabled reproduces it. This current-binary control does not prove when that separate exception was introduced. The passing run uses native `insertText:replacementRange:` to commit composition. Both failed variants and the control are recorded.

The test checks successful restart, not crash durability or body Undo/Redo execution. Evidence: `Tests/UserSchemeReview/round2/kingsbury/{prefix.h,probe.inc,output.txt,unmark-transitions.txt,unmark-control.txt,report.md}`.
