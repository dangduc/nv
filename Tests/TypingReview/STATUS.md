# Review status

PR: https://github.com/dangduc/nv/pull/24

## Round 1

Reviewed production commit `b3c2162`. All six perspectives wrote and ran probes.
[Findings comment](https://github.com/dangduc/nv/pull/24#issuecomment-5625499549).
[Fix results](https://github.com/dangduc/nv/pull/24#issuecomment-5625606503).

| Finding | Resolution |
| --- | --- |
| P1: quadratic link-record set comparisons on main | `5eda58b`: ordered linear comparison; 11 semantic cases pass. |
| P2: stranded Reveal after synchronous projection invalidation | `5eda58b`: refresh synchronous projections and resume explicit pending intents; 36 headless and 52 native editing checks pass. |
| P2: ignored caret clicks while link analysis is pending | `5eda58b`: place the caret without activating stale targets; 13 headless and 26 native checks pass. |

The original failing probes remain unchanged in `round1`.
Their reports distinguish reproduced defects from passing behavior.
The passing fix probes are in `fixes`.

## Round 2

Reviewed production commit `5eda58b`. All six perspectives wrote and ran new probes.
[Findings comment](https://github.com/dangduc/nv/pull/24#issuecomment-5625727721).
No additional actionable defect was confirmed, so no production change was needed between rounds two and three.

| Perspective | Executed evidence |
| --- | --- |
| Ousterhout | 24 pending-intent and nested-publication checks. |
| Luu | Changed-link, real-shift, immutable-snapshot, and cached-count measurements. |
| Torvalds | 12,006 differential cases and 598,715 checks under ASan/UBSan; negative control rejected. |
| Kingsbury | 24 asynchronous detach, reattach, source/syntax, and close interleavings under sanitizers; negative control rejected. |
| Contrarian async | 21 assertions over six word-count interest and observer transitions. |
| Contrarian UX | 19 native popup, shared-window count, note-switch, close, and reattach checks. |

Each report records its scope and limits under `round2`.

## Round 3

Reviewed `d93f935`, with production unchanged from `5eda58b`.
All six perspectives wrote and ran new probes. No additional actionable defect was confirmed.

| Perspective | Executed evidence |
| --- | --- |
| Ousterhout | 21 body/metadata ordering, duplicate suppression, exception recovery, and session identity checks. |
| Luu | 40 sustained deadline and metadata-burst checks across three sessions; maximum measured row-timer delay 104.982 ms. |
| Torvalds | 4,940 checks over 80 native text-storage/editor boundary cases under ASan/UBSan; three negative controls rejected. |
| Kingsbury | 1,389 checks across eight event orders and 48 browser histories under sanitizers; final state matches fresh projections. |
| Contrarian async | 39 copied-app checks across short/large Plain Text and Org sources; observed expensive calls use private worker storage, with exact editor/model text and final counts. |
| Contrarian UX | 13 candidate and 11 baseline native menu checks; no introduced defect confirmed. |

The menu probe cannot establish retained-menu activation safety: its fresh activation control also misses the intercepted launch boundary.
That limitation is recorded explicitly. Enabled retained menu items occur in both builds and are not treated as a new defect.
The final reviews and their evidence are posted in the PR conversation.
All three confirmed round-one findings were fixed before round two. Rounds two and three required no further production changes.
