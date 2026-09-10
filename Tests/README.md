# Multiple-window integration tests

Use macOS with full Xcode and an active desktop session. The bundled MultiMarkdown executable and OpenSSL archive require an Intel build; Apple Silicon Macs need Rosetta.

## Build and run

```sh
xcodebuild -project Notation.xcodeproj -scheme 'Notation Develop' \
  -derivedDataPath build/DerivedData ARCHS=x86_64 \
  MACOSX_DEPLOYMENT_TARGET=10.13 CODE_SIGNING_ALLOWED=NO \
  GENERATE_PROFILING_CODE=NO OTHER_CFLAGS= WARNING_LDFLAGS= build
python3 Tests/run-multiple-windows-tests.py
python3 Tests/run-regression-tests.py
```

The runner copies the app, gives it a separate preferences domain, and loads the test harness into that copy. It opens a temporary notes library. Startup hooks skip help import and external editor setup. The runner then launches the copy again to check saved windows, notes, and library switching. Run it outside a restrictive process sandbox so Rosetta can launch the app.

`compiler_support.py` supplies the header paths for standalone harness builds from `Sources/`, `Config/`, and `ThirdParty/`.

The suite exercises real nibs and Cocoa editors. It checks independent search, sorting and layout; shared text; undo; note switching; deletion; window closure; and restoration after relaunch. External updates enter through the note model. Marked-text tests check deferred updates, non-overlapping merges, and preserved conflict copies. External editor applications require separate manual checks with disposable notes.

## Review regression checks

The regression runner checks editor and preview ownership, incremental search, undo during composition, peer selections, bounded snapshot diffs, cached fonts, column settings, and query restoration. Ownership and restoration tests include mutations that must fail. See each `Tests/Regression/` directory for scope and commands. The source redesign has a [validation record](SourceViewerReview/VALIDATION.md). Historical defect reproducers are documented in `Tests/ReviewEvidence/README.md`.

## Fuzzy search checks

The [search test guide](FuzzySearch/README.md) covers native ordering, immutable corpus updates, duplicate result rows, persistence, and shared-source highlights.
These headless checks run natively on either architecture. CI runs them on Intel.
The separate copied-app probe requires an active desktop and working Intel runtime.

## Backup checks

The backup filesystem, scheduling, and Preferences checks use disposable state:

```sh
python3 Tests/BackupStore/run.py
python3 Tests/BackupStore/run-teardown.py
python3 Tests/BackupCoordinator/run.py
python3 Tests/BackupPreferences/run.py
python3 Tests/BackupArchive/native/run.py
```

After a Development build, `python3 Tests/BackupArchive/run.py` checks the actual library archive and restore paths in a copied app.
It requires the desktop session and Intel application runtime described above.
The filesystem suite injects interrupted writes and checks retention, corruption, ownership, and recovery into an empty folder.
The coordinator suite uses the production controller with a fake clock and controlled worker completions.
The native archive suite uses the production model and archive code with UI stubs and a test crypto provider.
It does not replace the copied-app checks of the shipping Intel/OpenSSL runtime or window and journal lifecycle.
The [backup review record](BackupReview/README.md) links review findings, corrections, and additional native probes.
Run those probes with `python3 Tests/BackupReview/run.py`.

## Native dependency replacements

Run `python3 Tests/Regression/native-dependencies/run.py` after a Development build.
The copied app checks detected links, disabled imports, and removal of sync, updater, and legacy preview commands.
Clipboard writes use a private test pasteboard.

## Source and viewer checks

The [source backspace checks](SourceBackspace/README.md) exercise deletion in a copied app with disposable notes.
They cover cached search backgrounds, Undo, shared editors, composition, and pending cleanup during note switches.
Run `python3 Tests/SourceBackspace/run.py` after a Development build.

The aggregate regression command also runs the following suites:

| Suite | Coverage |
| --- | --- |
| `source-highlighting/run.py` | Pinned parsers, UTF-16 ranges, incremental parsing, work limits, stale results, and temporary TextKit attributes. |
| `source-storage/run.py` | Original bytes, encodings, BOM, line endings, archive reopen, legacy sync migration, local syntax, and source export. |
| `org-preview/run.py` | Bundled Org helper hashes, deployment target, formatting, heading links and unique anchors, input/output limits, and literal code/includes. |
| `source-viewers/run.py` | Immutable snapshots, conversion, inert HTML, helper errors, timeouts, and cancellation. |
| `source-viewers/run-viewer.py` | Native WK viewer, local assets, remote blocking, Find, scroll, replacement, and teardown. |
| `source-workflow/run.py` | Real Source/Preview controls, shared edits, composition, independent syntax, and restoration. |

Set `NV_UI_ARTIFACTS` to an output directory when running `source-workflow/run.py` to capture the source and preview controls.
`preview-lifetime/run.py` checks lazy allocation and resource release for both Source-only and rendered browser windows.

## Native browser UI

The native UI checks cover search composition, explicit creation, title and tag edits, metadata undo, shared updates, appearance, and layout restoration. Control checks exercise menu dispatch, keyboard focus, and tag completion. Rendering checks compare URL and ordinary-text pixels across two windows. Every browser keeps the notes list above the editor. Old side-by-side layouts restore as a vertical stack.

The row checks require light backgrounds with dark titles in Aqua, and dark backgrounds with light titles in Dark Aqua. See `Tests/Regression/native-list/README.md` for the pixel thresholds and appearance checks.
The [appearance review record](NotesListAppearanceReview/README.md) contains both review rounds, executable evidence, and validation limits.

Run the focused checks after a Development build:

```sh
python3 Tests/Regression/native-list/run-native.py
python3 Tests/Regression/native-ui/run.py
python3 Tests/Regression/native-controls/run.py
python3 Tests/Regression/native-rendering/run.py
python3 Tests/Regression/user-schemes/run.py
```

The [User Scheme checks](Regression/user-schemes/README.md) cover separate light/dark colors, appearance changes, six preference controls, and persistence.

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

Keep library I/O in the application controller. Before opening another library, flush the current library and close its journal. Route view actions through their owning browser. Add a regression check when changing ownership or command routing.
