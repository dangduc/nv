# PR review record

PR: https://github.com/fastducduc/nv/pull/4

The review uses six engineering perspectives. These are analytical lenses, not reviews by the named people.

| Perspective | Focus |
| --- | --- |
| John Ousterhout | Module boundaries, hidden state, and lifecycle ownership |
| Dan Luu | Measured latency, resource costs, and boundary behavior |
| Linus Torvalds | Low-level correctness, ownership, compatibility, and error handling |
| Kyle Kingsbury | State transitions, persistence, concurrency, and failure recovery |
| Contrarian: remove complexity | Challenge requirements and unnecessary mechanisms |
| Contrarian: preserve user data | Challenge migration assumptions and compatibility claims |

Each round uses code probes. Confirmed findings become PR comments before delegated fixes.
Probe reports distinguish confirmed failures from rejected concerns and test limits.

## Round 1

Review baseline: `5e44a909bd6b7b2ad1957c475f94594e0bffd461`.
All six perspectives completed. Seven findings were confirmed and posted before fixes.

| Finding | Priority | PR comment |
| --- | --- | --- |
| Recovered HTML silently truncates large text | P2 | [Renderer](https://github.com/fastducduc/nv/pull/4#discussion_r3956235061) |
| Capture application stalls the UI thread | P2 | [Highlighting](https://github.com/fastducduc/nv/pull/4#discussion_r3956235093) |
| Older capture fallback replaces newer state | P2 | [Viewer state](https://github.com/fastducduc/nv/pull/4#discussion_r3956235106) |
| Delayed conversion overwrites external edits | P1 | [External source](https://github.com/fastducduc/nv/pull/4#discussion_r3956260022) |
| Encoding reinterpretation discards pending edits | P1 | [Pending source](https://github.com/fastducduc/nv/pull/4#discussion_r3956260026) |
| Untagged MacRoman fallback changes characters | P2 | [Import compatibility](https://github.com/fastducduc/nv/pull/4#discussion_r3956260031) |
| Deleted preview window leaves unused assets | P3 | [Resources](https://github.com/fastducduc/nv/pull/4#issuecomment-5582442127) |

Each perspective has its report and executable evidence under `round1/`.
The reports preserve the original observations, including tests that assert the pre-fix failure.

## Round 2

Review baseline: `f037c7b781fa2a3c58d7b00cb440ba3e7239b615`.
The clean build passed. Source storage passed 150 checks, highlighting passed 345, and the standalone viewer passed 142.
The renderer passed 113 checks. The clean bundle passed the removed-resource audit.

All six perspectives completed. Four findings came from the new review probes.
Two more state-consumer findings came from follow-up verification of the delegated viewer fix.
The workflow fixture's note-creation side effect was diagnosed separately and corrected.

| Finding | Priority | PR comment |
| --- | --- | --- |
| Loading capture supersedes pending exact state | P2 | [Repeated transitions](https://github.com/fastducduc/nv/pull/4#discussion_r3956449561) |
| Stale conversion offer recreates a deleted note | P2 | [Conversion lifetime](https://github.com/fastducduc/nv/pull/4#discussion_r3956536859) |
| Synchronization retry creates duplicate conflict notes | P2 | [Retry identity](https://github.com/fastducduc/nv/pull/4#discussion_r3956536868) |
| UTF-8 decoding removes a literal source character | P2 | [BOM decoding](https://github.com/fastducduc/nv/pull/4#discussion_r3956584009) |
| Hidden source layout replaces saved Source scroll | P2 | [Source position](https://github.com/fastducduc/nv/pull/4#discussion_r3956584017) |
| Pending return drops the Preview Find query | P2 | [Find restoration](https://github.com/fastducduc/nv/pull/4#discussion_r3956609738) |

The performance, low-level, and complexity-deletion reviews found no new defect in their bounded probes.
All six findings have delegated corrections. The rebuilt storage suite passed 235 checks, the standalone viewer passed 195, and the browser workflow passed 110.
The fix records preserve negative controls and explain the additional state and retry checks.

## Round 3

The final review will use the committed second-round corrections. Full aggregate validation will run alongside its independent probes.
