# Round 1 — contrarian review

No introduced actionable defect was found.
The review challenges whether removing the visible summary also removes its accessibility element and reserved space,
and whether the larger list interferes with existing keyboard selection or Create controls.

Reviewed production: `72c668cc5329ce6e48850377b35ec7d6d5b27d5b`, against base `4624b3d`.
The final run used checkout `612df045585d76d2a6d817d29b591cfe12614759`, which adds review evidence without changing production.
Relevant implementation: `Sources/Browser/AppController_BrowserUI.m:302–309`.

## Executable evidence

Run `python3 Tests/SearchSummaryReview/round1/contrarian/run.py` from an active desktop session.
The probe uses the actual Intel app, production search worker, disposable notes, and isolated preferences.
The shared harness serializes native launches with `build/pr-review/gui.lock`.

| Variant | Result |
| --- | --- |
| Production | 39 assertions pass, exit 0. |
| Restore only a visible summary label | Seven assertions pass; the residual accessibility-element assertion fails, exit 1. |
| Restore only the 24-point gap | Five assertions pass; the full-height list assertion fails, exit 1. |

At a 600-by-440-point content size, the list occupies all 154.5 points of its parent's height.
This remains true with results, duplicate selection, zero results, and an empty query.
The full window accessibility tree contains neither the status field nor its cell after successful search.
No exposed value, title, description, or help text repeats the removed count or ranking summary.

The fixture returns two occurrences of one note: title first, then fuzzy.
Native Down and Up events select the respective occurrence keys without replacing the shared source session or text storage.
Shift-Down selects both visible occurrences while the document projection still resolves to one note.

With no results, Create remains exposed to accessibility and its center passes native view hit testing.
The enlarged scroll view does not intercept that point.
Both the actual Create button action and Return from the native search editor add exactly one correctly titled note.
The original note's source remains unchanged.

## Baseline creation observation

With search autocomplete disabled, zero-result creation adds the note but leaves no selected note after fuzzy results publish.
`run-create-control.py` compares the current method with the exact previous `updateSearchAffordance` method from `4624b3d`, installed in the same copied app.
The old variant verifies that its visible summary and 24-point gap are active.
Both variants pass eight assertions and record the same state: two stored notes, two result occurrences, no pending search, and no selection.
This behavior is outside the introduced findings and no production fix is requested here.

The first main fixture dereferenced that absent selection with the C `titleOfNote` helper and crashed.
It now waits for current results and inspects the library's stored note title safely.
The initial crash and corrected selection diagnostic remain in the output directory.

## Identity and limits

Before/after hashes match, and the runner verifies production inputs against the reviewed commit.

| Input | SHA-256 |
| --- | --- |
| `AppController_BrowserUI.m` | `45b01fcb17f0df40c58689424053b9d221917f302571ab21ecb7afb40dc9e104` |
| `AppController_Search.m` | `c9140868ba8ff918e47f420bf7a33efed22232ec4bdcf77be075fbbad92f6a68` |
| `NotesTableView.m` | `775a9d9fbfa17ea7c7e0a4d27bb46c1cac2aac69032be712336f5df172d8992c` |
| `NVBrowserSession.m` | `2ec178fde253541204b26e36c3bfce018aacb17fe0469ceecd17bfa9ce91e170` |
| Development executable | `efc6fce32c2647e78909efe32d699737a58b3987cdc8b0ddb5fde753d67fdb99` |

Logs, hashes, and counts are under `build/SearchSummaryReview/round1/contrarian/`.
The tests ran on macOS 26.5.2 with Xcode 26.6.
Accessibility checks inspect AppKit's exposed object tree; they do not run VoiceOver.
Arrow events enter the production table's `keyDown:` method; Return uses the real field editor.
The button test combines native hit testing with `performClick:` rather than a hardware mouse event.
This bounded review does not retest pending/error transitions, older macOS versions, or shared-body Undo.
