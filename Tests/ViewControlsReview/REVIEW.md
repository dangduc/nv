# View controls review

PR: https://github.com/fastducduc/nv/pull/5
Production revision: `162c872` against `b27af28`.

The reviews use analytical perspectives inspired by John Ousterhout, Dan Luu, Linus Torvalds, and Kyle Kingsbury, plus a contrarian perspective.
They do not represent reviews or endorsements by those people.
Each perspective supplies executable evidence. Native probes use a copied Intel app, disposable notes, and separate preferences on macOS 26.5.2.

## Round 1

| Perspective | Evidence | Result |
| --- | --- | --- |
| State ownership | [Ousterhout report](round1/ousterhout/REPORT.md) | 39 checks; dropped-metadata mutation fails. |
| Performance | [Dan Luu report](round1/dan_luu/REPORT.md) | 58 checks; measured 1, 2, and 4 windows. |
| Correctness and menus | [Linus report](round1/linus/REPORT.md) | 67 native checks; 6 localized menu audits. |
| Reliability | [Kingsbury report](round1/kingsbury/REPORT.md) | 112 checks across 2 real launches; serialization mutation fails. |
| Contrarian integration | [Contrarian report](round1/contrarian/REPORT.md) | 184 checks in each of 6 localizations. |

No confirmed actionable findings require a production fix in round 1.
One initial Chinese-locale run failed to focus Search before any new View action. The unchanged repeat passed.
The report preserves the initial output and leaves its cause unresolved.

The [round 1 PR comment](https://github.com/fastducduc/nv/pull/5#issuecomment-5584555235) records these results.

## Round 2

| Perspective | Evidence | Result |
| --- | --- | --- |
| State ownership | [Ousterhout report](round2/ousterhout/REPORT.md) | 63 checks; wrong-browser syntax mutation fails. |
| Performance | [Dan Luu report](round2/dan_luu/REPORT.md) | 409 checks; 12 window lifecycle cycles, native edits, resize, and viewer measurements. |
| Correctness and menus | [Linus report](round2/linus/REPORT.md) | 327 invariant checks across 64 scenarios, including base controls. |
| Reliability | [Kingsbury report](round2/kingsbury/REPORT.md) | 43 checks across 2 launches; separate base and head viewport controls. |
| Contrarian integration | [Contrarian report](round2/contrarian/REPORT.md) | 206 checks through empty and closed-window states; hidden-title focus mutation fails. |

The focus control reproduced identical delayed body-focus losses in the base and PR apps at a 480-point window width.
It did not reproduce the single initial Search-focus failure from round 1.
The viewport control reproduced identical Source scroll loss when returning from Preview after relaunch in both apps.
These controls establish that the two reproducible behaviors predate the PR. Their reports preserve the observations and limits.

Neither round found a confirmed actionable defect in the changed production code.
There were no production-fix comments to assign to subagents, and no production fixes were made.
The evidence covers the stated histories on one macOS version. It does not establish correctness for every input method, timing, or failure condition.

## Application validation

The production code remains at `162c872`. Review commits add probes, reports, and recorded output.
The Intel Development build passed with Xcode 26.6 on macOS 26.5.2.
The multiple-window suite passed 35 checks and 13 relaunch checks. All 18 regression groups passed.
Expected failures from mutation controls appear in the regression output and are reported as successful controls.
The GitHub Intel build also passed for the first evidence commit, `d0365f4`.

## Reproduction

The shared [runner](run-probe.py) accepts a probe file and an optional instrumentation prefix.
Each report gives its exact command and scope. GUI runs share `build/pr-review/gui.lock`.
The runner removes its injected library from the environment before markup helpers run.
A probe can use multiple launches to retain its disposable files and preferences between processes.
