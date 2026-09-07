# Native browser UI review

This review covers the changes from `116daff` through `10de8a4`, followed by corrections from three review rounds.

The six AI review perspectives use methods associated with John Ousterhout, Dan Luu, Linus Torvalds, and Kyle Kingsbury. Two additional perspectives challenge workflow compatibility and the test evidence. The named people did not participate.

Each round records all six perspectives before corrections begin. Reports identify the reviewed source, executable probes, observed results, limitations, and actionable findings. GUI probes use copied apps, temporary notes, separate preferences domains, and `build/pr-review/gui.lock`.

Historical defect probes can fail after corrections. Use each report's reviewed revision and build instructions to reproduce its observations. Use `Tests/Regression/` for current acceptance checks.

## Review rounds

| Round | Reviewed production | Status |
| --- | --- | --- |
| 1 | `10de8a4` | All six perspectives complete. Five product defects and one test coverage gap corrected by three implementation agents. |
| 2 | Pending | Review follows the first corrections. |
| 3 | Pending | Review follows the second corrections. |

Round 1 reports: [Ousterhout](round1/ousterhout/report.md), [Luu](round1/luu/report.md), [Torvalds](round1/torvalds/report.md), [Kingsbury](round1/kingsbury/report.md), [workflow contrarian](round1/workflow_contrarian/report.md), and [test contrarian](round1/test_contrarian/report.md).

The [round 1 correction record](round1/corrections.md) maps each finding to its fix and acceptance evidence.

## Initial screenshots

These snapshots show the UI at `10de8a4`. The notes list stays white in both appearance modes.

![Light appearance](screenshots/light.png)

![Dark appearance with a white notes list](screenshots/dark.png)
