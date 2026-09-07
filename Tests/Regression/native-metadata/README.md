# Metadata undo

The native UI suite includes `checks.inc`. It sends Undo and Redo through the AppKit responder chain after Return commits title and tag edits.

The checks cover edit order across body and metadata changes, peer composition, external body updates, deletion, and window closure. A new browser must retain the metadata history from a closed browser. Lifetime checks observe browser, editor, note, and editing-session deallocation. Session teardown must clear both undo targets, with or without an explicit `close` call.

Metadata history uses the note undo manager. Its separate target borrows the editing session, so external body updates can discard body snapshots without discarding metadata history. Undo arguments contain a copied metadata value and a Boolean. They do not retain a note or browser.

After a Development build with the command in `Tests/README.md`, run:

```sh
python3 Tests/Regression/native-ui/run.py
python3 Tests/run-multiple-windows-tests.py
python3 Tests/run-regression-tests.py
```

The appearance checks use the native appearance callback. They do not call `browserAppearanceChanged` directly.
