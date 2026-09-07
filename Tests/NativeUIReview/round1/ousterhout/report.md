# Round 1: Design simplicity and ownership

AI review using John Ousterhout's design-simplicity perspective, not a statement from the person.

Reviewed production source `10de8a4` against `116daff`. Later review-only commits do not change the tested source. The probe compiles an x86_64 injection library, acquires the shared GUI lock, and runs a copied app with a unique bundle ID, temporary notes, and isolated defaults. No live sync account or external editor is used.

## Finding: P2 — Metadata undo is registered outside the active undo path

Location: `NVApplicationController.m:252-253`; related transition at `AppController_BrowserUI.m:191-193`.

Rename a selected note in the new title field and press Return. The title commits and focus moves to the body. The new metadata API registers undo in the library manager, but the focused body uses the note's editing session. Sending the real `undo:` action succeeds without restoring the title. Expected: the committed rename can be undone through the UI after its normal Return transition. Actual: the title stays renamed.

Evidence from `python3 Tests/NativeUIReview/round1/ousterhout/run.py`:

```text
UNDO BEFORE library=1 note=0 windowIsLibrary=0 windowIsNote=1
UNDO RESULT sent=1 title=Renamed Alpha expected=Alpha
PASS: library undo directly restores the title
```

The control call to the library manager proves that registration exists; the two undo domains disagree about the current operation. Integrate committed metadata with the selected note's undo behavior and test the responder action, including redo, instead of calling an internal manager alone. This finding corroborates the Torvalds review and should be posted once.

## Checked concerns without another finding

- Closing a browser with a pending title edit commits that title to the original note.
- Undo still works after the editing browser closes; the coordinator remains the undo target.
- The closed browser and editor both deallocate after bounded run-loop/autorelease draining. Immediate sampling initially missed AppKit's delayed editor release; an eight-second observation bound resolves that false alarm.
- An untouched title editor does not overwrite a model rename from another source. Its header refreshes when editing ends.

## Limits

The automated action uses AppKit's responder dispatch, not a physical keyboard event. The lifecycle check covers one additional browser. The external rename calls the model directly; it does not exercise a live sync service. The existing AppKit layout-recursion warning also appears; this probe does not establish its cause or user impact. The initial sandboxed run could not start the GUI and timed out; the reported results come from the approved outside-sandbox run.
