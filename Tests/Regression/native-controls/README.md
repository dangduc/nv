# Native control acceptance checks

The probe sends Search through the application menu after removing its toolbar item.
It checks that Search restores and focuses the field without changing the query or selection.
It also checks hidden toolbars, repeated Search commands, and a peer browser.

Keyboard checks send Tab through the actual search field editor, with and without a selected note.
Completion checks use the header field editor and existing library tags.
They cover multiple tags, duplicate exclusion, peer updates, and unchanged title dictionary completion.

After a Development build, run:

```sh
python3 Tests/Regression/native-controls/run.py
```

Use `--probe search`, `--probe tab`, or `--probe tags` to select one group.
Use `--app PATH` to select another build.
Each group rejects the preserved pre-correction app at `build/NativeUIReview/round1/nvALT.app`.

The runner uses a copied app, temporary notes, a unique preferences domain, and the shared GUI lock.
Normal startup services are disabled. The process has a 90-second timeout.

An earlier sequential run reported a Search focus failure while the peer browser remained active.
The intended window was not key, and its Search field had no editor.
The earlier runner used a fixed 50 ms delay without an activation assertion.

The runner now requests native activation and waits up to two seconds for the intended key window and active browser.
If this prerequisite fails, the probe stops before the menu action.
The probe does not assign the active browser directly or replace the menu action with a controller call.
