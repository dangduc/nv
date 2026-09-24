# Native control acceptance checks

The placement checks dispatch View > Search in Title Bar and cover both positions, resizing, focus, query selection, and peer windows.
They also check new windows and the Search command after hiding the toolbar. Run only these checks with `--probe placement`.
The multiple-window suite checks placement persistence after relaunch.

The probe sends Search through the application menu after removing its toolbar item.
It checks that Search restores and focuses the field without changing the query or selection.
It also checks hidden toolbars, repeated Search commands, and a peer browser.
The editor must be visible after Search, with at least 140 points of field width.
Later navigation to the body must retain focus after pending toolbar actions finish.

Keyboard checks send Tab through the actual search field editor, with and without a selected note.
The `--probe shift-tab` checks send Backtab events through the AppKit queue and cycle between Search and the open Source or Preview.
They also enter from the notes list, skip the empty body, restore hidden Search, and preserve body selection and text.
The `--probe arrows` checks require Up and Down to move list selection while Search retains focus and its query.
Both groups cover Exact and Fuzzy search, both layouts, both Search positions, and peer-window state.
The `--probe tab-preference` group checks the Editing radios, saved choices, and both Tab behaviors using queued key events.
It covers Option-Tab, Shift-Tab, shared-window edits, block Undo/Redo, Unicode, and line-ending boundaries.
With `NV_UI_ARTIFACTS`, it saves `tab-key-settings.png` from the Editing pane.
Completion checks use the header field editor and existing library tags.
They cover multiple tags, duplicate exclusion, peer updates, and unchanged title dictionary completion.

After a Development build, run:

```sh
python3 Tests/Regression/native-controls/run.py
```

Use `--probe search`, `--probe tab`, `--probe tags`, `--probe view`, `--probe new-note`, or `--probe command-return` to select one group.
Use `--app PATH` to select another build.
Set `NV_UI_ARTIFACTS` to an existing directory to save a screenshot of restored Search.
The Search, Tab, and Tags groups reject the preserved pre-correction app at `build/NativeUIReview/round1/nvALT.app`.

The runner uses a copied app, temporary notes, a unique preferences domain, and the shared GUI lock.
Normal startup services are disabled. The process has a 90-second timeout.

The New Note group sends Command-N through the application menu.
It checks focused Exact and Fuzzy queries, live field text, pending searches, and input-method composition.
It also checks empty queries, focus in other controls, and routing between browser windows.
New notes keep an empty body and Plain Text syntax. Pending search callbacks must preserve the new selection.

The Command-Return group sends keyboard events through `NSApplication` to the focused search field.
It covers Exact and Fuzzy matches, pending searches, live text, empty queries, and numeric-keypad Enter.
Plain Return still opens a matching note. Command-Return creates no note when another control has focus.
The new note must remain selected and visible. A second browser must keep its query and selection.

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

## Side notes list

Run `python3 Tests/Regression/native-controls/run.py --probe layout` for the restored side view.
The probe checks native menu routing, independent browser layouts, divider sizes, multiline fuzzy highlights, source and preview selection, and hidden lists.
Set `NV_UI_ARTIFACTS` to capture both Search placements with the side list.
The multiwindow suite checks layout and both divider sizes after relaunch.

## Adaptive list colors

Run `python3 Tests/Regression/native-controls/run.py --probe colors` for the body-derived list palette.
The probe checks both layouts, alternating and plain rows, and selected text with list focus, body focus, or an inactive window.
Two browser windows use opposite body palettes and window themes. Color changes must preserve the shared source.
The pixel checks also require column titles and header backgrounds to use the body palette.
Set `NV_UI_ARTIFACTS` to capture the four layout and palette combinations.

Run `--probe scrollbars` for the Use Neo Notational V Scrollbars setting.
WindowServer pixel checks cover matching gutters and header corners, contrasting thumbs, overlay transparency, and live palette changes in two windows and both list layouts.
The probe also checks native thumb hit targets, the Settings toggle, and unchanged shared source text.
With custom scrollbars disabled, it compares both panes with a standard macOS scroll view and requires the window's appearance, independently of the body palette. Overlay checks allow independent fades and compare the native shade over the same background.
Set `NV_UI_ARTIFACTS` to save custom and native scrollbar captures in both palettes and layouts.
