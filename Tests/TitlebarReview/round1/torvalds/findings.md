# Round 1: Torvalds perspective

Reviewed `6b8d67514f4fc5bc2e9fca22816a32f30f59fb1c` against upstream `89d9abe`.
This review applies a simplicity, concrete correctness, and compatibility perspective. It does not impersonate Linus Torvalds.

No actionable production defect found in this review's scope.

## Executable evidence

Run from the repository root after the Development build:

```sh
python3 Tests/TitlebarReview/round1/torvalds/availability.py
python3 Tests/TitlebarReview/round1/torvalds/run.py
```

The actual copied Intel app passed 54 assertions on macOS 26.5.2 with Xcode 26.6.
The probe uses disposable notes, a unique preferences domain, and the shared GUI lock.

- The ordinary `NSToolbarItem` remains enabled after `validateVisibleItems`; its search field remains enabled and editable.
- Search dispatch through the real main menu focuses the native search field editor. Later body focus remains stable.
- Each removed icon command retains a live, enabled menu receiver: New Note, Preview, Rename, Tags, Copy Note Link, Export, and Delete.
- Real Rename and Tags commands focus the selected note's fields. Preview enters the viewer and returns to source.
- A new browser ignores a saved legacy toolbar with action icons and a hidden state. It displays only Search and preserves the old preferences.
- With two browsers, Search reaches the active browser. New Note creates there, preserves the other browser's selection, and retains its keyboard shortcut.

The extracted, unchanged production toolbar method also compiles for macOS 10.13 with unguarded availability diagnostics treated as errors.
A negative control removes only the macOS 11 guard. Compilation then fails for `setToolbarStyle:` and `NSWindowToolbarStyleUnifiedCompact`.
This proves that the availability check can detect a missing guard.

## Source and result record

Relevant code: `Sources/Browser/AppController_BrowserUI.m:335`, `Sources/Browser/AppController.m:2013`, and `Sources/Application/NVApplicationController.m:105`.

The checked toolbar source SHA-256 is `6a179cb93dfe10052bb894b077cb969a1a748862646adbe35cec4b4cdcf1a33a`.
The runtime probe SHA-256 is `26af7fb2ffa5529bb1adb64ec576b2c1a338be235d1d5c161a8a7a6cb63f8bf0`.
The extracted method SHA-256 is `07b381b88a44ff9a96402cbf0eb893edcd7fc84a052d03851478e567138b79a7`.

Generated logs, hashes, compiler commands, and results are under `build/TitlebarReview/round1/torvalds/`.
The runtime result reports exit 0 and `TORVALDS_REVIEW_PASS checks=54`.
The availability result reports production exit 0 and negative-control exit 1.

## Limits

The first sandboxed launch exited before any app assertion. The authorized unsandboxed copied-app launch passed.
The app ran on macOS 26.5.2. SDK availability compilation does not establish visual behavior on macOS 10.13.
Export, Copy Note Link, and Delete checked real menu receiver resolution and validation; the probe did not execute those effects.
This focused review does not cover the separate shared-body Undo failure reproduced on the unchanged base.
