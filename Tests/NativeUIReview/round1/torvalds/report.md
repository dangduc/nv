# Native UI review, round 1

Perspective: implementation correctness and simplicity, inspired by Linus Torvalds. This is an AI review, not his review.

Scope: `10de8a4` against `116daff`. The probe uses the existing x86_64 Development app on macOS 13.7.8.

## P2: Committed metadata cannot be undone from the resulting focus

Source: `NVApplicationController.m:252-256`, with `AppController_BrowserUI.m:191-193`.

Trigger: rename a note, press Return, then use Undo. Return commits the title and focuses the body.

Actual: Undo is disabled. A direct responder-chain Undo also leaves the renamed title unchanged. The metadata operation exists in the library undo manager. The body uses the note editing session instead.

Expected: Undo after Return restores the previous title. Title and tags need an undo route that the resulting first responder can reach.

Evidence from `run.log`:

```text
OBSERVATION metadata: libraryCanUndo=1 bodyCanUndo=0 bodyIsFirstResponder=1
OBSERVATION metadata after responder-chain Undo: title=Renamed Alpha expected=Alpha
PASS: library undo can restore the committed title
```

The probe uses the real title field editor and its Return command. It sends Undo through `NSApp`, without choosing an undo manager. The existing native UI test calls the library manager directly and misses this routing failure.

## P2: Search command cannot restore a removed toolbar item

Source: `AppController.m:1888-1902` and `AppController.m:2063`.

Trigger: remove Search through toolbar customization, leave the toolbar visible, then use the Search command.

Actual: Search remains absent and receives no focus. `dualFieldIsVisible` reports toolbar visibility, so the command skips the helper that restores the Search item.

Expected: the Search command restores and focuses Search regardless of the toolbar item configuration.

Evidence from `run.log`:

```text
PASS: toolbar remains visible after removing Search
OBSERVATION search after Search command: present=0 focused=0 window=(null) query=al
PASS: visibility helper can restore and focus Search
```

The probe removes the item through the public `NSToolbar` API, then calls the same action as the Search menu command. It does not automate the customization palette.

## Reproduction and limits

```sh
python3 Tests/NativeUIReview/round1/torvalds/run.py
```

The command exits 1 because both behavior checks fail. It takes the shared GUI lock and uses a copied app with a unique identifier. Notes, support files, defaults, and temporary files are disposable.

The successful evidence run used desktop access. The first sandboxed app launch stalled before application output and was stopped.

The probe also confirms that metadata commits, direct library undo, and explicit Search restoration work. Static ownership inspection found no additional issue in the retained metadata binding or toolbar item references.

This review does not establish behavior on macOS 10.13 or newer AppKit versions. The existing layout-recursion warning also appeared, but this probe does not establish its cause or impact.
