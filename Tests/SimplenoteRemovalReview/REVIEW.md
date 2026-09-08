# Simplenote removal review

This record covers three review rounds of the Simplenote removal PR.
The named perspectives guide independent assistant reviewers. The named people did not participate or endorse the reviews.

Base: `9693356` (master before removal). Initial implementation: `f38a8cb3f1e5f74c57cfe5e8d5791f364201f1cb`.
The preserved old app at `build/SyntaxFlickerReview/fix.app` has the same relevant pre-removal behavior.
The initial implementation app is preserved at `build/SimplenoteRemovalReview/round1.app`.

Initial CI passed: [run 34270057388](https://github.com/fastducduc/nv/actions/runs/34270057388).
The Intel build and packaging succeeded; the master-only tag job was skipped.

Each reviewer writes and runs original code. Reports record commands, results, limitations, and actionable findings.
GUI probes use copied apps, isolated settings, disposable notes, and the shared `build/pr-review/gui.lock`.
Reports distinguish product defects from probe errors and expected behavior after feature removal.

| Round | Status |
| --- | --- |
| 1 | Complete; fixture finding corrected and validated |
| 2 | Complete; no actionable introduced defect found |
| 3 | In progress |

The review perspectives are John Ousterhout, Dan Luu, Linus Torvalds, Kyle Kingsbury, a data-preservation skeptic, and a workflow-compatibility skeptic.

## Planned coverage

| Perspective | Round 1 | Round 2 | Round 3 |
| --- | --- | --- | --- |
| Ousterhout | Archive boundaries and model contracts | Cross-layer ownership and compatibility contract challenges | Final API and migration invariants |
| Dan Luu | Repeated archive/save work and data growth | File-storage and edit/write operation counts | Final resource and rewrite stability |
| Torvalds | Project, resource, and binary integration | Local actions, exports, external editing, and callers | Final integration and clean build closure |
| Kingsbury | Journal recovery and deletion ordering | Failed writes, retry, close, and library replacement | Final recovery histories and fixes |
| Data-preservation skeptic | Old archive compatibility and metadata removal | Encryption, source encodings, and downgrade assumptions | Challenge data-preservation claims and fixtures |
| Workflow skeptic | Preferences, toolbar restoration, and navigation | Local workflows after sync UI removal | Final UI/command behavior and fixes |

Coverage can change when evidence identifies a more useful independent question.
Each later round also checks any changes made after earlier findings.

## Round 1

| Perspective | Report | Result |
| --- | --- | --- |
| John Ousterhout | [Archive contracts](round1/ousterhout/REPORT.md) | No introduced application defect found |
| Dan Luu | [Repeated saves and reopen work](round1/dan_luu/REPORT.md) | No introduced application defect found |
| Linus Torvalds | [Build and native interface closure](round1/linus/REPORT.md) | No introduced application defect found |
| Kyle Kingsbury | [Crash and recovery histories](round1/kingsbury/REPORT.md) | No introduced application defect found |
| Data-preservation skeptic | [Old archive challenge](round1/contrarian_data/REPORT.md) | Permanent fixture used an unregistered service key |
| Workflow-compatibility skeptic | [Toolbar, windows, preferences, and quit](round1/contrarian_workflow/REPORT.md) | No introduced application defect found |

The [fixture finding](https://github.com/fastducduc/nv/pull/7#issuecomment-5591045833) was posted and corrected by a delegated subagent.
The old-app producer passed 12 checks. The updated source-storage suite passed 273 checks.
The permanent guard rejects the preserved original flawed fixture. Application code is unchanged by this correction.
Round 2 app reviews can proceed because this correction changes test fixtures and their preconditions, not application code.

## Round 2

| Perspective | Report | Result |
| --- | --- | --- |
| John Ousterhout | [Library replacement and shared editing](round2/ousterhout/REPORT.md) | 115 checks per app; no introduced defect found |
| Dan Luu | [Plain-file persistence counts](round2/dan_luu/REPORT.md) | 78 checks per app; write counts and bytes match |
| Linus Torvalds | [External editing and export](round2/linus/REPORT.md) | 82 checks per app; no introduced defect found |
| Kyle Kingsbury | [Failed snapshots and recovery](round2/kingsbury/REPORT.md) | 71 assertions per app; WAL and dirty state survive failed stores |
| Data-preservation skeptic | [Encrypted archive compatibility](round2/contrarian_data/REPORT.md) | 24 producer, 56 current-reader, and 38 old-reader checks passed |
| Workflow-compatibility skeptic | [Storage and Security actions](round2/contrarian_workflow/REPORT.md) | 54 current checks and 55 baseline checks, including one baseline adapter check |

Round 2 found no actionable introduced defect. No application fix was requested.
Existing equality and canceled-picker-queue behavior are recorded with baseline controls in the reports.
CI passed for the round 1 correction: [run 34272904963](https://github.com/fastducduc/nv/actions/runs/34272904963).
