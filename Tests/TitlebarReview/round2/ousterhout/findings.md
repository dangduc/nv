# Round 2: design and ownership review

Perspective: John Ousterhout's emphasis on simple interfaces and explicit ownership. This review does not represent him.

Reviewed head: `2566d427ba3d7ace7e12b672bf6ab0fd5f08d845`. Its production change is `6b8d675`, compared with upstream `89d9abe`.

## Findings

No actionable defect found within these ownership, detachment, and native validation boundaries.

The container adds no mutable controller state. The toolbar delegate returns the same browser-owned item after removal. Native toolbar validation preserves the editable, targetless search field.

Normal window closure releases the complete toolbar ownership graph. This extends round 1, whose extracted-method fixture explicitly detached the toolbar before controller teardown.

Relevant locations:

- `Sources/Browser/AppController_BrowserUI.m:335`: migration and ownership of the field and container.
- `Sources/Browser/AppController_BrowserUI.m:386`: reuse of the existing Search item.
- `Sources/Browser/AppController.m:2013`: synchronous focus after native layout.
- `Sources/Browser/AppController.m:2192`: Search reinsertion.
- `Sources/Browser/AppController.m:1893` and `:1931`: window closure and controller teardown.

## Executable evidence

Run this command from the repository root in an active desktop session:

```sh
python3 Tests/TitlebarReview/round2/ousterhout/run.py
```

The runner uses the existing copied-app harness and its shared `build/pr-review/gui.lock`. Each process uses one disposable note and a unique application defaults domain.

| Case | Result |
| --- | --- |
| Production: four secondary-browser cycles | 168 assertions passed, exit 0 |
| Deliberate field-to-controller retain cycle | 39 assertions passed, then the controller-release assertion failed, exit 1 |

Each production cycle covers these cases:

- Remove Search during native query editing, then restore it through the Search command.
- Preserve a Unicode query, the current selection, field identity, container identity, and browser delegates across reinsertion.
- Detach and reattach the entire toolbar during query editing.
- Complete focus synchronously and preserve a later body-focus command through event processing.
- Call native toolbar validation with a selected note and with no selected note.
- Close a secondary window while Search owns its field editor, without explicit toolbar removal or field-editor cancellation.
- Preserve the shared library, surviving browser state, note count, title, and body.

After four closures, witnesses observed four deallocations for each object type: controller, field, item, container, and toolbar. Each close removed only its browser's layout manager from the shared text storage.

The witnesses retain names only. The negative control adds one strong field-to-controller edge through an associated object. This cycle prevents controller deallocation, and the probe detects it.

## Source record and limits

The six production source hashes match before and after both runs. `build/TitlebarReview/round2/ousterhout/results.json` records those hashes, probe hashes, commands, exit codes, and assertion counts. Detailed output remains beside that file.

The probe ran in the Intel Development app on macOS 26.5.2 (25F84), with Xcode 26.6 (17F113). The app contains production change `6b8d675`. This review made no production edits.

Toolbar removal and whole-toolbar detachment use native AppKit APIs as lifecycle stress cases. The fixed toolbar does not expose customization to users. These results do not cover IME composition, VoiceOver, older macOS releases, or arbitrary replacement toolbars.

Two fixture assumptions needed correction. Query typing can change selection before toolbar removal, so the assertion now captures selection immediately before removal. AppKit releases toolbar views after controller deallocation, so the fixture permits up to 40 run-loop ticks of 50 ms. Initial failure logs remain in the output directory.

No production change requested by this review.
