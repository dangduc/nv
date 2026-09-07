# Multiple-window integration tests

Use macOS with full Xcode and an active desktop session. The bundled frameworks require an Intel build; Apple Silicon Macs need Rosetta.

## Build and run

Create `SimperiumConfig.h` from `SimperiumConfig-example.h` if it does not exist. Keep existing configuration files.

```sh
xcodebuild -project Notation.xcodeproj -scheme 'Notation Develop' \
  -derivedDataPath build/DerivedData ARCHS=x86_64 \
  MACOSX_DEPLOYMENT_TARGET=10.13 CODE_SIGNING_ALLOWED=NO \
  GENERATE_PROFILING_CODE=NO OTHER_CFLAGS= WARNING_LDFLAGS= build
python3 Tests/run-multiple-windows-tests.py
python3 Tests/run-regression-tests.py
```

The runner copies the app, gives it a separate preferences domain, and loads the test harness into that copy. It opens a temporary notes library. Startup hooks skip help import, external editor setup, and update checks. The runner then launches the copy again to check saved windows, notes, and library switching. Run it outside a restrictive process sandbox so Rosetta can launch the app.

The suite exercises real nibs and Cocoa editors. It checks independent search, sorting and layout; shared text; undo; note switching; deletion; window closure; and restoration after relaunch. External updates enter through the note model. Marked-text tests check deferred updates, non-overlapping merges, and preserved conflict copies. Live sync services and external editor applications require separate manual checks with disposable notes.

## Review regression checks

The regression runner checks editor and preview ownership, incremental search, undo during composition, peer selections, cached fonts, column settings, and query restoration. Ownership and restoration tests include mutations that must fail. See each `Tests/Regression/` directory for scope and commands. Historical defect reproducers are documented in `Tests/ReviewEvidence/README.md`.

## Ownership rules

`NVApplicationController` owns one `NotationController` and the open browsers. Each `AppController` has an `NVBrowserSession` for its query, filtered list, sort and previews. The initial MainMenu owner remains the bridge to application preferences and status UI. Localized `BrowserWindow.xib` files contain the reusable window interface.

`NVNoteEditingSession` owns shared text and up to 200 undo actions per note. Each browser attaches a separate layout manager. When switching notes, remove that layout manager from its old storage and add it to the new storage. `replaceTextStorage:` moves all attached layout managers.

Keep library I/O and sync startup in the application controller. Before opening another library, flush the current library and close its journal. Route view actions through their owning browser. Add a regression check when changing ownership or command routing.
