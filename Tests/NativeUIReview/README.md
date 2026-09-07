# Native browser UI review

This review covers the changes from `116daff` through `10de8a4`, followed by corrections from three review rounds.

The six AI review perspectives use methods associated with John Ousterhout, Dan Luu, Linus Torvalds, and Kyle Kingsbury. Two additional perspectives challenge workflow compatibility and the test evidence. The named people did not participate.

Each round records all six perspectives before corrections begin. Reports identify the reviewed source, executable probes, observed results, limitations, and actionable findings. GUI probes use copied apps, temporary notes, separate preferences domains, and `build/pr-review/gui.lock`.

Historical defect probes can fail after corrections. Use each report's reviewed revision and build instructions to reproduce its observations. Use `Tests/Regression/` for current acceptance checks.

## Initial screenshots

These snapshots show the UI at `10de8a4`. The notes list stays white in both appearance modes.

![Light appearance](screenshots/light.png)

![Dark appearance with a white notes list](screenshots/dark.png)
