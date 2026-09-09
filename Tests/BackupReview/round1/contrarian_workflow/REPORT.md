# Round 1: contrarian workflow and minimalism review

Reviewed `30c3cf816c80e4ff957223d55f22b36074880ef1` for PR #8 against `119c453`.
This review challenges user-action ordering and whether tests reproduce native editing behavior.

## Finding: [P2] A backup silently discards an active retention edit

Location: `Sources/Preferences/NVBackupPreferencesViewController.m:174`, with action forwarding at line 254.

When a user edits a retention count or storage target, the value saves only after the field editor ends editing.
`refreshControls` disables every numeric field when the coordinator becomes busy.
AppKit detaches the active field editor without sending `controlTextDidEndEditing:` in this sequence.
The next refresh overwrites the typed value with the previous saved setting.
An automatic backup can therefore erase a setting while the user types.
The manual button also forwards its action before ending field editing, so that backup uses the previous retention policy.

The executable probe uses the production pane in a native `NSWindow` with a real `NSTextField` field editor.
It types `7` into Recent, whose saved value is `96`, through `NSTextView insertText:replacementRange:`.
It then exercises two paths:

- A backup-status notification changes busy to true, then false. The field reverts to `96`, with zero end-edit callbacks.
- The native Back Up Now button receives `performClick:`. The action sees `96`; the following busy transition erases `7`.

Preserve active numeric edits across an asynchronous busy transition.
Before an explicit action, validate and commit its pending field edit so the action receives the intended policy.
Invalid input must stop that action, and an old library's field edit must still be rejected after a switch.

## Executable evidence

`python3 Tests/BackupReview/round1/contrarian_workflow/run.py` passed its baseline reproduction assertions:

```text
REPRODUCED: automatic busy transition; typed=7, completion field=96, saved=96, end-edit callbacks=0
REPRODUCED: manual button; typed=7, completion field=96, saved=96, end-edit callbacks=0, action retention=96
```

`python3 Tests/BackupReview/round1/contrarian_workflow/run.py --expect-fixed` failed as intended:
`Busy transition preserves and eventually commits the user's retention edit`.
This mode can verify a subsequent correction.

These existing suites also passed:

- `python3 Tests/BackupPreferences/run.py`
- `python3 Tests/BackupCoordinator/run.py`

The existing preference helper directly invokes begin/end-edit delegates without attaching a field editor.
That test does not expose the asynchronous edit-loss sequence reproduced here.

## Scope and limits

The new probe executes production pane code and native AppKit editing.
Its coordinator is an in-memory fake, and its manual action models the production ordering at `NVBackupController.m:273–277`.
The coordinator suite executes the real coordinator with fake notes, storage, clock, and queues.
No full Intel app, note archive, password dialog, or restore-library switch runs in this review.

The disabled/manual, stale-library, and unavailable-destination checks passed in their existing harnesses.
No additional actionable issue was established for those contracts.
The unchanged-checkpoint retention issue already reported by another reviewer is not duplicated here.
