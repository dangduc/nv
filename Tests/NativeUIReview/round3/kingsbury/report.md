Round 3 found no actionable defect in two closure histories followed by a process relaunch.
The final run passed 52 assertions: 26 in each process. Both processes exited 0.

This AI review uses a state-consistency perspective inspired by Kyle Kingsbury. He did not participate.
The reviewed repository revision is `0afeb03837b94c1a16da211a79c9eaf8dfe51183`, against baseline `116daff`.
Production source and the existing Development app remain unchanged from `12936fed78e1d98ac646bb88b51e009609ad505e`.
The app executable SHA-256 is `f9d0a299a852c80fae0574722776d5e732031fec6f4c328861e57d74d9d00228`.
The run used macOS 13.7.8, Xcode 15.2, and Rosetta.
This review changed only files in `Tests/NativeUIReview/round3/kingsbury/`.

| Case | Expected and observed result |
| --- | --- |
| The origin edits its note body, leaves a native title edit pending, then closes. | Closure commits `Closed Alpha` and retains the exact body `alpha anchor body local edit`. |
| The peer composes native tags while its note receives an external body snapshot, then closes the last window. | Closure commits `closed, durable` and retains the exact body `beta shared external text`. No browser remains open. |
| The application reopens two browsers, assigns independent queries and divider heights, then quits normally. | A fresh process restores exactly two notes with the original UUIDs. It restores the exact titles, tags, and bodies from both closure cases. |
| The fresh process reads restored browser controls and geometry. | Queries remain `anchor` and `shared`. Selected note UUIDs and body ranges agree. Divider heights remain 160 and 238 points. Both white lists remain above their editors. |

The metadata closure checks cover `AppController_BrowserUI.m:167-179`, `AppController_MultipleWindows.m:70-73`, and `AppController.m:1760-1767`.
The probe requires a pending native field editor before each closure.
The tags case also requires marked text while the external body snapshot reaches the visible editor.
Neither case explicitly commits metadata before `NSWindow performClose:`.

The durable checks cover the normal termination path at `NVApplicationController.m:276-284` and `AppController.m:1805-1830`.
The first process calls `NSApp terminate:` after both replacement browsers reach their expected state.
It does not manually flush notes, save application window state, or close the journal before termination.
The second process opens the same temporary library through `NotationController` and reads the restored model.
An independent fixture file contains expected UUIDs and geometry. It does not supply application state during restoration.

Browser restoration covers `NVApplicationController.m:184-200` and `AppController_MultipleWindows.m:97-166`.
The probe compares each visible search field with its browser session query.
It also compares the selected note identity, native metadata controls, body text, and body selection range.
The geometry assertions read actual view frames and require a full-width list above a body editor at least 100 points high.
The white-list assertions read the notes table background and the Aqua appearance of its containing view.
The table background assignment is at `AppController.m:2143`.

Run the probe from the repository root with desktop execution permitted:

```sh
python3 Tests/NativeUIReview/round3/kingsbury/run.py > Tests/NativeUIReview/round3/kingsbury/run.log 2>&1
```

The final output contains:

```text
PASS: closing the origin commits its pending title and retains its earlier body edit
PASS: closing the last browser commits composed tags and retains the external body snapshot
ROUND 3 KINGSBURY PHASE 1 PASSED (26 checks), requesting normal application termination
PASS: both durable notes preserve their original UUIDs without duplication
PASS: fresh model restores the title committed on closure and the exact local body edit
PASS: fresh model restores tags committed on closure and the exact external body snapshot
DURABLE browser=0 query=anchor title=Closed Alpha tags= body=alpha anchor body local edit divider=160.00
DURABLE browser=1 query=shared title=Beta tags=closed, durable body=beta shared external text divider=238.00
ROUND 3 KINGSBURY PHASE 2 PASSED (26 checks)
```

The initial fixture read the legacy `notesScrollView` background for its white-list assertion.
That outlet returned `nil` in the reopened browsers. The initial fixture interpreted the missing color as zero brightness.
The corrected fixture reads the actual notes table background and records white brightness `1.000` in both processes.
`fixture-initial.log` preserves the rejected assumption. That failure does not establish a product defect.

The runner obtains `build/pr-review/gui.lock` and uses one copied app with a unique defaults domain per run.
Both phases share that domain and temporary notes directory. Launch Services starts each process through `open -W -n`.
The probe requires actual key-window and main-window ownership before browser operations. It never assigns the application's active-browser state.
Startup explicitly skips sync services and external editor initialization.
Each process has a 90-second timeout. The runner deletes the defaults domain after both phases.

These histories cover orderly window closure and normal application termination, not process crashes or sudden storage loss.
The external update enters through `NoteObject setContentString:`. This review does not cover a sync transport or an external editor.
The probe uses AppKit field-editor calls and window closure, not physical keyboard input or a live input-method session.
The white-list check reads control properties and geometry, not screenshot pixels.
The baseline app was not run. The review establishes the observed persistence behavior on the current production app.
The existing AppKit layout-recursion warning appeared at startup. This review did not establish its cause or impact.
