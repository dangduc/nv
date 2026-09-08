This review uses a Kyle Kingsbury-inspired perspective. It does not represent a review or statement by Kyle Kingsbury.

The Round 2 histories found no introduced regression in the PR application at `162c872`, compared with the source base at `b27af28`.
The main probe completed 43 checks across two real application processes: 19 checks in phase 1 and 24 checks in phase 2.
The runner reused one disposable notes directory, one copied application, and one unique defaults domain across each pair of processes.

The histories extended Round 1 into these cases:

- One browser used Source. The other browser used a Markdown Preview of a different long note.
- Both browsers hid Title, Tags, body controls, word count, and the notes list.
- A Syntax command reached the active Preview browser through the application coordinator while the body controls stayed hidden.
- JSON syntax affected only the selected note. The other note retained Plain Text syntax, and the Preview retained its Markdown format.
- Visibility and syntax changes preserved both exact source bodies and independent source selections.
- The visible Source viewport stayed at 500 points after the list and header collapsed.
- Normal relaunch restored both modes, note identities, hidden controls, local syntax, source bodies, and selections.
- A completed DOM capture restored the Preview viewport at 700 points after relaunch.
- Note deletion started with an outstanding exact viewport capture. Shared visibility changes occurred before deletion Undo.
- Deletion Undo restored the note body and JSON syntax. The other Source browser retained its note, body, and selection.
- List expansion after these histories restored separate heights of 125 and 175 points.

The primary command returned 0. Its complete output is in `output.txt`.

```sh
python3 Tests/ViewControlsReview/run-probe.py \
  --probe Tests/ViewControlsReview/round2/kingsbury/probe.m \
  --app build/ViewControlsReview/round1/nvALT.app --launches 2 \
  > Tests/ViewControlsReview/round2/kingsbury/output.txt 2>&1
```

The first run stopped at a separate Source viewport assertion after relaunch. Its output remains in `initial-scroll-observation.txt`.
The saved hidden Source viewport started at 650 points. The return from restored Preview reached 0 points in the collapsed layout.
The probe now records this observation without classifying it as a PR regression.

A separate control used identical code on the base and PR applications. This control uses no new visibility actions or preferences.
Both applications stored 650 points before relaunch. Both applications returned to 44 points after relaunch, with the source selection intact.
This comparison establishes that Source viewport loss across this restoration path predates the PR.
The collapsed history produced a different clamp value. These controls do not isolate the reason for that difference.

The base application came from the prior PR4 artifact at `d5fc585`.
`git diff b27af28 d5fc585 -- Sources` returned no differences.

Both control commands returned 0. They report observations, so their success does not assert viewport preservation.

```sh
python3 Tests/ViewControlsReview/run-probe.py \
  --probe Tests/ViewControlsReview/round2/kingsbury/scroll-control.m \
  --app build/ViewControlsReview/base/nvALT.app --launches 2 \
  > Tests/ViewControlsReview/round2/kingsbury/scroll-control-base.txt 2>&1

python3 Tests/ViewControlsReview/run-probe.py \
  --probe Tests/ViewControlsReview/round2/kingsbury/scroll-control.m \
  --app build/ViewControlsReview/round1/nvALT.app --launches 2 \
  > Tests/ViewControlsReview/round2/kingsbury/scroll-control-head.txt 2>&1
```

Both control logs contain this observation:

```text
CONTROL observed post-relaunch Source scroll=44; expected=650
```

The environment used macOS 26.5.2 and Xcode 26.6, build 17F113. The Intel Development applications ran under Rosetta.
The runner serialized desktop access through `build/pr-review/gui.lock`.

The histories used explicit window-state saves, defaults synchronization, note flushes, and journal closure before process exit.
They do not establish crash durability, power-loss behavior, disk-error recovery, or behavior during concurrent external writes.
The deletion history proves that a capture was outstanding before deletion. It does not force a particular WebKit callback order after deletion.
No production code changed during this review.
