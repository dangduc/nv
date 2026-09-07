# Multiple-window integration tests

Use macOS with full Xcode and an active desktop session. The bundled frameworks require an Intel build; Apple Silicon Macs need Rosetta.

## Build and run

Create `Config/SimperiumConfig.h` from `Config/SimperiumConfig-example.h` if it does not exist. Keep existing configuration files.

```sh
xcodebuild -project Notation.xcodeproj -scheme 'Notation Develop' \
  -derivedDataPath build/DerivedData ARCHS=x86_64 \
  MACOSX_DEPLOYMENT_TARGET=10.13 CODE_SIGNING_ALLOWED=NO \
  GENERATE_PROFILING_CODE=NO OTHER_CFLAGS= WARNING_LDFLAGS= build
python3 Tests/run-multiple-windows-tests.py
python3 Tests/run-regression-tests.py
```

The runner copies the app, gives it a separate preferences domain, and loads the test harness into that copy. It opens a temporary notes library. Startup hooks skip help import, external editor setup, and update checks. The runner then launches the copy again to check saved windows, notes, and library switching. Run it outside a restrictive process sandbox so Rosetta can launch the app.

`compiler_support.py` supplies the header paths for standalone harness builds from `Sources/`, `Config/`, and `ThirdParty/`.

The suite exercises real nibs and Cocoa editors. It checks independent search, sorting and layout; shared text; undo; note switching; deletion; window closure; and restoration after relaunch. External updates enter through the note model. Marked-text tests check deferred updates, non-overlapping merges, and preserved conflict copies. Live sync services and external editor applications require separate manual checks with disposable notes.

## Review regression checks

The regression runner checks editor and preview ownership, incremental search, undo during composition, peer selections, bounded snapshot diffs, cached fonts, column settings, and query restoration. Ownership and restoration tests include mutations that must fail. See each `Tests/Regression/` directory for scope and commands. Historical defect reproducers are documented in `Tests/ReviewEvidence/README.md`.

## Native browser UI

The native UI checks cover search composition, explicit creation, title and tag edits, metadata undo, shared updates, appearance, and layout restoration. Control checks exercise menu dispatch, keyboard focus, and tag completion. Rendering checks compare URL and ordinary-text pixels across two windows. Every browser keeps the notes list above the editor. Old side-by-side layouts restore as a vertical stack.

The row checks require pale backgrounds and dark title glyphs in both appearances. See `Tests/Regression/native-list/README.md` for their pixel thresholds and negative control.

Run the focused checks after a Development build:

```sh
python3 Tests/Regression/native-ui/run.py
python3 Tests/Regression/native-controls/run.py
python3 Tests/Regression/native-rendering/run.py
```

For full-screen transitions and light/dark snapshots, use an unlocked desktop session:

```sh
mkdir -p build/native-ui-artifacts
NV_UI_FULL_SCREEN=1 NV_UI_ARTIFACTS="$PWD/build/native-ui-artifacts" \
  python3 Tests/Regression/native-ui/run.py
```

The optional full-screen run uses Launch Services. The UI runners use a shared lock to prevent concurrent keyboard-focus changes.

Compare two builds with the same temporary library of 10,000 notes:

```sh
python3 Tests/Regression/native-ui/run.py --benchmark --app /path/to/baseline/nvALT.app
python3 Tests/Regression/native-ui/run.py --benchmark
```

The benchmark reports median and p95 times for four queries and for table scrolling with bitmap capture. Bitmap capture does not measure animation frame rate.

## Ownership rules

`NVApplicationController` owns one `NotationController` and the open browsers. Each `AppController` has an `NVBrowserSession` for its query, filtered list, sort and previews. The initial MainMenu owner remains the bridge to application preferences and status UI. Localized `BrowserWindow.xib` files contain the reusable window interface.

`AppController_BrowserUI.m` replaces the legacy window layout with a native toolbar, metadata header, and `NSSplitViewController`. Each browser stores its own divider height. Appearance changes affect the editor display without changing shared note text.

`NVNoteEditingSession` owns shared text and up to 200 undo actions per note. Each browser attaches a separate layout manager. When switching notes, remove that layout manager from its old storage and add it to the new storage. `replaceTextStorage:` moves all attached layout managers.

Keep library I/O and sync startup in the application controller. Before opening another library, flush the current library and close its journal. Route view actions through their owning browser. Add a regression check when changing ownership or command routing.
