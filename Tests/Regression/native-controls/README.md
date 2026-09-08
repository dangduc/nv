# Native control acceptance checks

The probe sends Search through the application menu after removing its toolbar item.
It checks that Search restores and focuses the field without changing the query or selection.
It also checks hidden toolbars, repeated Search commands, and a peer browser.
The editor must be visible after Search, with at least 140 points of field width.
Later navigation to the body must retain focus after pending toolbar actions finish.

Keyboard checks send Tab through the actual search field editor, with and without a selected note.
Completion checks use the header field editor and existing library tags.
They cover multiple tags, duplicate exclusion, peer updates, and unchanged title dictionary completion.

After a Development build, run:

```sh
python3 Tests/Regression/native-controls/run.py
```

Use `--probe search`, `--probe tab`, `--probe tags`, or `--probe view` to select one group.
Use `--app PATH` to select another build.
Set `NV_UI_ARTIFACTS` to an existing directory to save a screenshot of restored Search.
The Search, Tab, and Tags groups reject the preserved pre-correction app at `build/NativeUIReview/round1/nvALT.app`.

The runner uses a copied app, temporary notes, a unique preferences domain, and the shared GUI lock.
Normal startup services are disabled. The process has a 90-second timeout.

An earlier sequential run reported a Search focus failure while the peer browser remained active.
The intended window was not key, and its Search field had no editor.
The earlier runner used a fixed 50 ms delay without an activation assertion.

The runner now requests native activation and waits up to two seconds for the intended key window and active browser.
If this prerequisite fails, the probe stops before the menu action.
The probe does not assign the active browser directly or replace the menu action with a controller call.

The restored toolbar item also needs window layout before its field can receive focus.
Search completes this layout and focuses an available field directly.
The native expansion runs only for a hidden or compressed field, to avoid a delayed focus change after body navigation.

The View group sends the visibility, Source/Preview, and Syntax Type commands through the application menu.
It checks active-browser routing, single-choice syntax, shared preferences, and new-window defaults.
Hidden header rows must release body space. The notes list must retain its saved height without changing the window frame.
Metadata checks cover pending edits, untouched fields, Rename, Tags, and New Note with a hidden title.
Word Count must release its temporary substring observers before other shared editing operations.

The View group runs before the Search group changes the toolbar. Its wide window keeps Search expanded before header commands. Its peer retains the minimum window width.
With `NV_UI_ARTIFACTS`, this group also saves the expanded and collapsed note views.
