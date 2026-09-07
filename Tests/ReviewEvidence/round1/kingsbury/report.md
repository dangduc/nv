# Round 1: state consistency and operation ordering

AI review perspective inspired by Kyle Kingsbury. No participation or endorsement by the named person is implied.

Reviewed commit: `30791c5`, compared with `4c6cf45`.

## P1: Undo discards an external update received during composition

Location: `NVNoteEditingSession.m:73-77`; the editor invokes this path through `LinkingEditor.m:61`.

`restoreContents:` replaces the shared storage and writes it to the note without resolving marked text or `pendingExternalContents`. Normal commits check both conditions. An undo command can therefore overwrite incoming content that was deferred to protect an active composition.

The Cocoa probe uses two browser windows attached to the same note:

1. Start with `base`; insert ` committed` and confirm ordinary undo and redo work.
2. Start native marked text with a `draft ` prefix.
3. Deliver an external model update containing `base committed REMOTE`.
4. Invoke the composing editor's `undo:` action.
5. Finish the composition and commit pending changes.

Expected: Undo affects local edits. The external text remains in the original note or a preserved conflict copy.

Actual: Undo changes both the editor and model to `base`. The pending commit clears the deferred contents. There is one note, containing no `REMOTE` text. The deferred update receives no conflict copy. Both browser editors agree on this loss, so agreement alone does not establish preservation.

Coordinate undo and redo with composition finalization and deferred external updates before consuming history. Add a regression assertion that checks preservation of external text after this ordering.

## Executable evidence

Run after the documented Development build, outside the restrictive process sandbox:

```sh
python3 Tests/ReviewEvidence/round1/kingsbury/run-probes.py
```

The runner copies the app, uses a random preferences domain and temporary notes, and serializes GUI access with `build/pr-review/gui.lock`. The Cocoa subprocess has a 90-second timeout.

Result: exit 0; 13 assertions passed. Assertions labeled `BUG` confirm the defect in the reviewed snapshot; they are reproduction checks, not acceptance tests.

Relevant output:

```text
EVIDENCE after-undo marked=0 editor=base model=base
EVIDENCE after-unmark editor=base model=base notes=1
KINGSBURY ROUND 1 PROBES COMPLETED (13 checks)
```

## Coverage with no finding

The same run confirmed ordinary edits propagate to both windows, ordinary undo and redo update the model, and external model updates initially leave active marked text intact. No live sync service, crash recovery, or external editor application was exercised. The defect is demonstrated through the note model's existing external-update entry point.
