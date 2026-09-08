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

The ownership review confirmed a repeated-transition ordering defect and separately diagnosed a workflow-fixture error.
[The new PR comment](https://github.com/fastducduc/nv/pull/4#discussion_r3956449561) has a delegated fix.
The performance and low-level reviews found no new defect in their bounded probes.
Durability and the two contrarian reviews remain in progress.

## Round 3

Pending the second round's fixes.
