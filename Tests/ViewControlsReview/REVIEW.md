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
The report preserves the initial output and leaves its cause unresolved. Round 2 compares this boundary with the base app.

## Reproduction

The shared [runner](run-probe.py) accepts a probe file and an optional instrumentation prefix.
Each report gives its exact command and scope. GUI runs share `build/pr-review/gui.lock`.
The runner removes its injected library from the environment before markup helpers run.
A probe can use multiple launches to retain its disposable files and preferences between processes.
