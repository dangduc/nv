# Round 2: library ownership and editing boundaries

This review uses John Ousterhout's design principles as a lens. It does not represent his participation or endorsement.

Reviewed production commit: `f38a8cb3f1e5f74c57cfe5e8d5791f364201f1cb`.
The round 1 fixture correction and evidence commit `b418d84` leaves production code unchanged.
The comparison source is `9693356`.
The frozen comparison app was built from `65e1608`, whose production tree matches that comparison source.

## Result

No actionable introduced defect found in this bounded scope.

The removal leaves local ownership in the existing coordinator, browser, library, and editing-session interfaces.
The deleted `startSyncServices` and `stopSyncServices` implementations managed remote sessions and their power callbacks.
They did not own editor attachment, local observer removal, or the local write queue.

The original native probe passed **115 assertions in each app**, including two harness setup checks.
It completed three consecutive library replacements with two real browser windows.
Each replacement reused the selected note's UUID for a different model object and different source.

| Boundary | Native observation | Relevant source |
| --- | --- | --- |
| Shared editing | Two independent layouts share one session; switching one window leaves its peer attached | [AppController.m](../../../../Sources/Browser/AppController.m#L1186) |
| Library replacement | Marked text commits to the original note before both windows detach | [NVApplicationController.m](../../../../Sources/Application/NVApplicationController.m#L185) |
| Session shutdown | Each observed session closes once, releases source analysis, clears its Undo targets, and loses both layouts | [NVNoteEditingSession.m](../../../../Sources/Editor/NVNoteEditingSession.m#L329) |
| Model identity | The matching UUID receives a new session associated with the new model and library | [NVApplicationController.m](../../../../Sources/Application/NVApplicationController.m#L254) |
| Late notifications | A delayed old-model change executes but cannot reload the closed session or alter the active source, selection, syntax, tags, count, or cache | [NVNoteEditingSession.m](../../../../Sources/Editor/NVNoteEditingSession.m#L329) |
| Peer closure | Closing and reopening the second browser detaches and reattaches one layout; shared source Undo and Redo still work | [AppController_MultipleWindows.m](../../../../Sources/Browser/AppController_MultipleWindows.m#L41) |

## Executable evidence

[checks.inc](checks.inc) drives actual native editors, browser windows, coordinator library replacement, and model notifications.
Each history performs these steps:

1. Edit one source and verify the peer receives the same committed characters.
2. Switch the peer to another note and return, checking the exact layout attachments.
3. Prepare an independent library with a new model that deliberately has the old UUID.
4. Start native marked-text composition in the peer and replace the active library.
5. Check the original note's final source, old session cleanup, and both replacement editors.
6. Schedule an old-model change after replacement and verify isolation.
7. Exercise source Undo and Redo, then close and recreate the peer window.

[prefix.h](prefix.h) counts session closure and post-closure reloads without replacing normal behavior.
It also gives each synthetic library a journal directory inside its temporary notes directory.
This permits preparing the replacement before closing the active library without a fixture-only collision in the application's shared cache journal.
All normal journal, model, coordinator, and editor implementations still run.

The `--retain-obsolete-observer` control deliberately reattaches the old session's model observer after normal closure.
The old-model update then reaches that session, and the callback-count assertion fails.
This demonstrates that the probe detects the cleanup contract it claims to test.
The failure is an intentional probe mutation, not a production defect.

An earlier probe scheduled its synthetic callback directly on `NoteObject`.
A baseline rerun then failed when Foundation's timer cancellation compared that target with a deallocating `NotationPrefs`.
The legacy `NoteObject` equality method assumes another UUID-bearing object and sent `uniqueNoteIDBytes` to the preferences object.
That equality implementation is unchanged by this PR.
The [preserved failure log](baseline-direct-note-timer.log) records the stack.
The final probe schedules through a neutral helper that retains the note and invokes the same model update.
This avoids adding a note target to Foundation's delayed-selector registry; it does not alter production equality or observer behavior.

| Run | Result | Log |
| --- | --- | --- |
| Current app | 115 checks, exit 0 | [current.log](current.log) |
| Baseline app | 115 checks, exit 0 | [baseline.log](baseline.log) |
| Obsolete-observer control | Expected failure at `closed session receives no old-model notification callbacks`, exit 1 | [negative.log](negative.log) |

Run from the repository root:

```sh
python3 Tests/ViewControlsReview/run-probe.py \
  --probe Tests/SimplenoteRemovalReview/round2/ousterhout/checks.inc \
  --prefix Tests/SimplenoteRemovalReview/round2/ousterhout/prefix.h \
  --app build/SimplenoteRemovalReview/round1.app

python3 Tests/ViewControlsReview/run-probe.py \
  --probe Tests/SimplenoteRemovalReview/round2/ousterhout/checks.inc \
  --prefix Tests/SimplenoteRemovalReview/round2/ousterhout/prefix.h \
  --app build/SyntaxFlickerReview/fix.app

python3 Tests/ViewControlsReview/run-probe.py \
  --probe Tests/SimplenoteRemovalReview/round2/ousterhout/checks.inc \
  --prefix Tests/SimplenoteRemovalReview/round2/ousterhout/prefix.h \
  --app build/SimplenoteRemovalReview/round1.app \
  --launch-arg=--retain-obsolete-observer
```

Executable SHA-256 values:

- Current: `d61aea6619f6c4322efac164d7409ac131aa0ce2a8760d874850c34443331ede`
- Baseline: `ee8e9ca27c99d55ff867afabd49e75c12f5548f49ac93dc733f514f477cac365`

## Limits

The probe deliberately retains old model and session objects to deliver and observe late callbacks.
It therefore makes no claim about their final deallocation or retained memory.
The delayed callback is a synthetic local model update, not an external editor process or a removed network service.
The journal-path substitution excludes shared-cache handoff behavior from this evidence.
Three bounded histories do not test every input method or arbitrary callback ordering.
Viewer callbacks, crash recovery, encrypted archives, and remote account migration belong to other review scopes.
