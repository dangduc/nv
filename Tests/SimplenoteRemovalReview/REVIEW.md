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
| 3 | Complete; no actionable introduced defect found |

The review perspectives are John Ousterhout, Dan Luu, Linus Torvalds, Kyle Kingsbury, a data-preservation skeptic, and a workflow-compatibility skeptic.

## Review coverage

| Perspective | Round 1 | Round 2 | Round 3 |
| --- | --- | --- | --- |
| Ousterhout | Archive boundaries and model contracts | Cross-layer ownership and compatibility contract challenges | Browser deletion and shared editing ownership |
| Dan Luu | Repeated archive/save work and data growth | File-storage and edit/write operation counts | Deletion-history object and persistence counts |
| Torvalds | Project, resource, and binary integration | Local actions, exports, external editing, and callers | Packaged app and retained dependency boundaries |
| Kingsbury | Journal recovery and deletion ordering | Failed writes, retry, close, and library replacement | Legacy migration followed by crash recovery |
| Data-preservation skeptic | Old archive compatibility and metadata removal | Encryption, source encodings, and downgrade assumptions | Challenge data-preservation claims and fixtures |
| Workflow skeptic | Preferences, toolbar restoration, and navigation | Local workflows after sync UI removal | Last-window commands and persistence |

Each reviewer selected bounded experiments from the code changes and prior evidence.
Round 3 independently rechecked the fixture correction.

## Round 1

[Published PR comment](https://github.com/fastducduc/nv/pull/7#issuecomment-5591154023).

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

## Round 2

[Published PR comment](https://github.com/fastducduc/nv/pull/7#issuecomment-5591374716).

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

## Round 3

| Perspective | Report | Result |
| --- | --- | --- |
| John Ousterhout | [Browser deletion and shared editing](round3/ousterhout/REPORT.md) | 154 assertions per app; missing deletion Undo control fails |
| Dan Luu | [Deletion-history resource counts](round3/dan_luu/REPORT.md) | 42 current assertions; 43 in each baseline control; local journal counts match |
| Linus Torvalds | [Final artifact and retained dependencies](round3/linus/REPORT.md) | 52 artifact and 35 native dependency assertions; three resource controls fail |
| Kyle Kingsbury | [Migration and crash recovery](round3/kingsbury/REPORT.md) | 73 assertions; losing the WAL fails source preservation |
| Data-preservation skeptic | [Independent fixture challenge](round3/contrarian_data/REPORT.md) | 100 assertions; six metadata variants and the local sequence control detected |
| Workflow-compatibility skeptic | [Commands after all browsers close](round3/contrarian_workflow/REPORT.md) | 48 assertions per app; missing URL reveal fails exact note selection |

All 18 reviews are complete. Round 3 found no new actionable defect.
The only requested correction was the permanent fixture precondition gap. A subagent fixed it, and an independent reviewer verified it.
No application-code changes were required after the initial implementation.
CI passed for the round 2 evidence: [run 34274565611](https://github.com/fastducduc/nv/actions/runs/34274565611).
