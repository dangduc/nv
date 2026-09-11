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

The P3 many-paragraph cost is under attribution and correction before round three.
A same-app control keeps character wrapping active and disables only the glyph adjustment.
The original round-two results remain unchanged.

## Round 3

Pending the round-two findings and dispositions.
