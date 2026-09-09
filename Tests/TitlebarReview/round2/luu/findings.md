# Round 2 — actual browser geometry and measurement

Perspective: Dan Luu's emphasis on measured behavior. This report does not speak for him.

No actionable finding in the changed toolbar geometry or focus behavior.
The review compares production commit `6b8d67514f4fc5bc2e9fca22816a32f30f59fb1c` with `89d9abe`.
The measured checkout was `2566d427ba3d7ace7e12b672bf6ab0fd5f08d845`, which adds the first review reports.
No production file changed during this review.

The new probe uses the built Intel app under Rosetta, with its real browser, notes list, source editor, and HTML preview.
The common runner copies the app, creates a unique preferences domain, and isolates notes, support files, and temporary files.
It holds `build/pr-review/gui.lock` throughout each app run.
This round extends the first round's blank AppKit fixture with actual browser content and view transitions.

From an active desktop session, run:

```sh
python3 Tests/TitlebarReview/round2/luu/run.py
```

The completed run passed 746 checks on macOS 26.5.2 (25F84), with Xcode 26.6 (17F113).
The matrix contains 224 resize commands and 448 geometry observations.
Each command has an observation immediately after `setFrame:display:` returns and another after explicit layout and event processing.
The matrix combines these states:

- Source and a completed HTML preview.
- A visible or hidden notes list.
- Visible or hidden title, tags, and body controls.
- An empty query or a matching 1,024-character query in Exact mode.
- Body focus or the active native search editor.
- Window widths of 480, 780, 1,200, 1,600, 1,200, 780, and 480 points.

All observations retained the same dimensions for each window width.
The leading offset was 89 points, the trailing margin was 8 points, and the field height was 24 points.
The immediate and settled dimensions differed by zero points.
The field remained attached and occupied its entire container.
Every resize preserved the query, selected note, body mode, and search editor focus state.
The complete 6,347-character HTML source and the single fixture note remained unchanged.

| Window width | Search width |
| --- | --- |
| 480 points | 383 points |
| 780 points | 683 points |
| 1,200 points | 1,103 points |
| 1,600 points | 1,503 points |

The implementation supports this result.
`Sources/Browser/AppController_BrowserUI.m:345` creates the container, and lines 349–354 constrain all four field edges.
Lines 357–358 permit the item to expand beyond its minimum width.
`Sources/Browser/AppController.m:2015` completes window layout before the Search command focuses the native field.
The window retains the note title while `Sources/Browser/AppController_BrowserUI.m:362` hides its title-bar display.

The independent negative control caps the item's maximum width at 325 points without changing its field constraints.
At a 1,200-point window width, it produced a 325-point field and a 786-point trailing gap.
The production geometry assertion rejected that result, and the control exited with status 1 as expected.

The probe also records synchronous resize and explicit layout time.
These samples contain actual browser work, with 112 commands per body mode.

| Body mode | Median | p95 | Maximum |
| --- | --- | --- | --- |
| Source | 7.670 ms | 9.909 ms | 13.918 ms |
| HTML Preview | 6.566 ms | 7.684 ms | 8.073 ms |

These times exclude event-loop completion, compositor presentation, and preview load time.
The modes ran sequentially, without a paired base-commit timing run.
The samples establish neither a toolbar cost difference nor a frame-rate guarantee.
The probe uses one small note and programmatic resizing.
It does not cover mouse-drag live resize, full screen, appearance changes, large libraries, or older macOS versions.
The runner substitutes isolated startup paths and suppresses external editor initialization and delayed startup actions.

Two initial attempts exposed an incorrect provider assumption in the probe.
The first completed all geometry observations but failed a final assertion against a cached preview provider.
The second waited on that same closed provider.
`Sources/Browser/AppController.m:1215` discards the viewer when search clears selection.
`Sources/Browser/AppController_Preview.m:112` creates the replacement after note selection returns.
The corrected probe retrieves the current provider after each query transition and waits for its completed HTML render.
Both failed attempt logs remain in the output directory as harness evidence.
This provider mismatch is not a finding against this PR.

The following SHA-256 hashes were identical before and after the completed run:

| Input | SHA-256 |
| --- | --- |
| `Sources/Browser/AppController_BrowserUI.m` | `6a179cb93dfe10052bb894b077cb969a1a748862646adbe35cec4b4cdcf1a33a` |
| `Sources/Browser/AppController.m` | `46a9c9f6f0aee838d547dd7b0ef17fa80f97978e1e951ffa0dca91229dac67be` |
| `Sources/UI/DualField.m` | `6617a4b656f5d55587ac0ee374148efdbc906772c9f3e2ace1ab9a205dd6f9c8` |
| Built `nvALT` executable | `5b672807c892a9e12b8b1ce8291f17853bb93780cd4caf80946885198e47d8ca` |

Raw logs, geometry, timings, and identity records are in `build/TitlebarReview/round2/luu/`.
The completed records are `production.log`, `width_cap_negative_control.log`, `result.json`, and `summary.json`.
