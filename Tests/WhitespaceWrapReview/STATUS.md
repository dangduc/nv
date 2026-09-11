# Review status

PR: https://github.com/dangduc/nv/pull/25

## Round 1

Reviewed commit: `83a7307`, based on merged master `f772c4b`.
All six perspectives wrote and ran independent evidence.
[Posted findings](https://github.com/dangduc/nv/pull/25#issuecomment-5627522767).

| Perspective | Result |
| --- | --- |
| Ousterhout | 162 copied-app ownership/layout checks passed; baseline wrapping negative control failed as expected. |
| Luu | 810 native layout stages passed; P3 slow reflow for very long contiguous-space paragraphs. |
| Torvalds | 4,755 checks per architecture passed with ASan and UBSan; no finding. |
| Kingsbury | Candidate/base passed 492/490 composition-history checks; 32 recorded states matched exactly. |
| Contrarian UX | P2: the 40th space after `alpha beta` moves an already-fitting word to the next line. |
| Contrarian platform | 12,693 native font, glyph, bidi, and protected-whitespace assertions passed; no additional finding. |

The correction adds native character wrapping to the common source paragraph style.
Words can split at the window edge. This avoids a custom typesetter.
The rebuilt app passed all 843 original wrapping checks.
Both findings are addressed in the [round-one correction](fixes/round1/README.md).
The fitting-word probe passed 223 checks.
The copied-app reflow measurement fell from 64.00 ms to 10.30 ms for 32,768 spaces at a 464-point container width.
Each of the three compared app variants passed 586 checks.
A follow-up allocation probe confirmed that 10,000 attribute requests now share one immutable paragraph style.
The corrected native-editing contract checks character wrapping and preserves all other native paragraph values.
[Posted correction](https://github.com/dangduc/nv/pull/25#issuecomment-5627675301).

## Round 2

Reviewed production commit: `072a6bc`.
All six perspectives wrote and ran code against the corrected character-wrapping implementation.

| Perspective | Result |
| --- | --- |
| Ousterhout | 42 copied-app ownership, normalization, and state checks passed; no finding. |
| Luu | Four app runs passed 826 checks each; P3 approximately 10% extra resize work for 1,024 mixed paragraphs. |
| Torvalds | 4,894 assertions per architecture with ASan/UBSan passed; no finding. |
| Kingsbury | Candidate/base passed 974/972 composition-history checks; all 72 recorded states matched. |
| Contrarian UX | 2,881 checks and 1,440 native key events passed; no finding. |
| Contrarian platform | 19,193 assertions across 48 narrow-width matrices passed; no introduced finding. |

The [round-two correction](fixes/round2/perf/correction.md) mitigates the P3 finding.
A same-app control attributed the increment to the glyph path.
The callback now skips ineligible batches and uses a 64-property stack buffer with a heap fallback.
Measured scoped malloc calls fell from 2,064,738 to 1,161, and resize work fell 4.60%.
The large-note resize path remains slow; that residual cost is documented rather than reported as eliminated.
The buffer-equivalence suite passed 465 guarded checks and 271 native-layout checks under ASan/UBSan.
The original round-two results remain unchanged.
[Posted mitigation and limit](https://github.com/dangduc/nv/pull/25#issuecomment-5627957999).
[Posted findings](https://github.com/dangduc/nv/pull/25#issuecomment-5627833420).

## Round 3

Reviewed production commit: `4b72537`.
All six perspectives wrote and ran new evidence against the final implementation.
No new actionable findings were reported.

| Perspective | Result |
| --- | --- |
| Ousterhout | 117 copied-app checks passed across shared-editor attachment, font changes, and buffer regeneration. |
| Luu | Short-note timing runs passed 1,552 checks per app; separate allocation runs passed 134 each. Small-batch heap allocations fell from 112 to zero. |
| Torvalds | 8,843 assertions per architecture passed with ASan/UBSan and stack-lifetime checks. |
| Kingsbury | Both copied apps passed 874 composition-owner closure checks; all 84 source/model/selection states matched. |
| Contrarian UX | 2,802 checks and 1,644 native key events passed; Backspace retraced nine observed space-wrap boundaries. |
| Contrarian platform | 56,330 assertions across 28 live edit phases passed; 12,298 sampled hit-test results matched the prior implementation. |

Each perspective's code, results, and limits are under [round3](round3/).
All three rounds are complete, with corrections between rounds.
These are subagent engineering perspectives, not reviews or endorsements from the named people.
The round-two large-note resize cost remains documented as mitigated, not eliminated.
Short-note timing samples do not establish a regression or improvement.
Automated geometry checks do not verify every painted caret frame or behavior on macOS 13.
