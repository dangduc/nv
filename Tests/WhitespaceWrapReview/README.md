# Space-wrapping review evidence

PR: https://github.com/dangduc/nv/pull/25

Each round uses six engineering perspectives: John Ousterhout, Dan Luu, Linus Torvalds, Kyle Kingsbury, and two contrarians.
The named perspectives are review prompts, not claims of authorship or endorsement by those people.
Each perspective writes and runs a focused probe against the production change.

Reviews distinguish confirmed defects, measured limits, and cases the probes do not establish.
The production code remains fixed during each round.
Confirmed findings receive a fix or a documented disposition before the next round starts.

Each perspective has a `findings.md`, executable `run.py`, and its source evidence.
Generated executables, large logs, and full timing trials belong under ignored `build/WhitespaceWrapReview/`.
Copied-app probes use temporary libraries and isolated preferences.
Desktop probes share `/Users/duc/dev/nv/build/pr-review/gui.lock` to avoid conflicting focus changes.

The [status record](STATUS.md) links the posted findings and their dispositions.
