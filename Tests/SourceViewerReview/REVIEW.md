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

Review baseline: `9720676ccd0e619dba99f6a47d257216c1e383eb`.
All six perspectives completed. Two findings were confirmed and delegated for correction.
The baseline passed all 18 aggregate groups, 48 multiple-window checks, 14 CI unit tests, and packaged-app validation.
GitHub's Intel build also passed.

Two findings were posted before delegated corrections:

| Finding | Priority | PR comment |
| --- | --- | --- |
| Joined capture replaces its caller's newer Find query | P2 | [Per-caller state](https://github.com/fastducduc/nv/pull/4#discussion_r3956760254) |
| Signed archive encoding changes unchanged source bytes | P2 | [Encoding identity](https://github.com/fastducduc/nv/pull/4#discussion_r3956760257) |

The ownership probe reproduces the Find failure through production provider methods and the actual browser consumer.
The encoding probe reproduces changed GB 18030 bytes after an ordinary archive round trip.
Its local comparison control passes all 262 checks; three independent negative controls fail.

The performance review passed 41 assertions in three runs with actual TextKit layout.
Work stayed equal across two document lengths at the same saved viewport depth.
The full-document negative control failed its measured-work assertion.

The failure-recovery review passed 112 checks with 32 failures injected at the production WAL synchronization boundary.
It covered edited and deleted conflict copies, separate origin identities, and three archive reopen cycles.
Neither probe found another actionable defect within its stated limits.

The complexity-deletion review passed 27 runtime checks with four provider lifetimes.
Hidden Source edits caused no renderer submissions or periodic DOM reads. Closed providers left no timer callbacks.
The forced hidden-poll control failed its intended assertion.

The user-data review passed 95 checks across seven editing histories with two attached layouts.
Undo, Redo, syntax changes, archive restoration, and closure retained the expected source bytes.
The newline-normalization control failed its first Undo assertion.
Neither contrarian review found a new defect within its stated limits.

## Corrections

The three rounds produced 15 findings: seven, six, and two.
Every finding received a delegated correction after its PR comment was posted.
The correction records link the original failure, the production change, and the regression evidence.
Historical reports retain baseline failures and rejected concerns.

The final encoding correction passes 262 extracted-production checks and all 243 actual-app storage checks.
The viewer correction preserves each caller's Find query through exact replies, timeout, and a return before completion.
The native viewer passed 207 checks. The corrected browser fixture passed 136 checks twice and its queued-refresh control passed 137.
See the `round3/linus/FIX.md` and `round3/ousterhout/FIX.md` records for those corrections.
The [validation record](VALIDATION.md) contains the final combined build and suite results.
