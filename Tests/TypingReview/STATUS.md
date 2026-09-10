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
