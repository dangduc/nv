# Round 1: workflow contrarian review

Reviewed production `10de8a4` against merged baseline `116daff`. This is an AI skeptical workflow perspective, not a real person's review. Three focused Cocoa probes use a copied app, unique bundle identifier, temporary notes/defaults, a unique pasteboard, disabled delayed services, and the shared GUI lock. No production files were changed.

## Findings

### P2: Tab cannot leave an empty persistent search for a selected note

Select a note from the unfiltered list, focus Search, and press Tab. The current build keeps the field editor focused. The baseline moves focus to the body. The old guard in `AppController.m:1058-1062` consumes Tab when the field is empty. The selection change at `AppController.m:1321-1333` now preserves an empty query instead of displaying the selected title, making this guard reject a valid selected-note workflow. Permit this transition when a current note exists, while retaining the empty/no-selection behavior.

`tab-current.log`: `TAB_EMPTY expected=body actual=NSTextView`, with a non-null search editor; exit 1. `tab-baseline.log`: `expected=body actual=body currentEditor=0x0`; exit 0, six checks. Nonempty-query Tab passes both builds. The probe sends `insertTab:` through the actual field editor, not directly to the controller delegate.

### P2: The relocated tag editor loses library tag completion

Create an existing `workflow` tag, select another note, invoke Tag Note, type `wor`, and invoke completion. The baseline completes to `workflow`; the new field completes to the dictionary word `works`. `AppController.m:761-762` redirects single-note tagging away from `NotesTableView`, whose completion provider is at `NotesTableView.m:1147-1175`. The plain header field in `AppController_BrowserUI.m:101-112` has no equivalent library-tag completion provider. Connect the new field's completion delegate to the existing tag source.

`tags-current.log`: `expected=workflow actual=works delegate=NSTextField`; exit 1. `tags-baseline.log`: `expected=workflow actual=workflow delegate=NotesTableView`; exit 0, four checks. The probe calls the real editor's `complete:` command.

## Other checks and limitations

Unfiltered-origin plain-text clipboard import passes five checks: one shared note is created, its complete body survives, the originating browser selects it, and the other browser retains its Beta query and selection (`paste-unfiltered-current.log`). A filtered-origin variant failed to reveal the imported note in both builds; this is not reported as an introduced regression. Its reveal path depends on key-window state in this background Cocoa runner. No HTTP import, live sync, global clipboard, or external editor was used. Existing AppKit layout-recursion logging was observed but not counted as a new finding.

## Reproduction

Run from the repository root with GUI execution allowed. The runner obtains `build/pr-review/gui.lock`.

```sh
NV_WORKFLOW_PROBE=tab python3 Tests/NativeUIReview/round1/workflow_contrarian/run.py
NV_WORKFLOW_PROBE=tags python3 Tests/NativeUIReview/round1/workflow_contrarian/run.py
NV_WORKFLOW_PROBE=paste python3 Tests/NativeUIReview/round1/workflow_contrarian/run.py
```

Append `--app build/UIDerivedDataBaseline/Build/Products/Development/nvALT.app` for the baseline. Set `NV_WORKFLOW_FILTERED=1` for the filtered clipboard variant recorded in `paste-current.log` and `paste-baseline.log`.
