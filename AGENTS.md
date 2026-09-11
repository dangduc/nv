# Repository Guidelines

## Project Structure & Module Organization

nvALT is a macOS Cocoa application written primarily in Objective-C, with C utilities. Application code lives in `Sources/`, grouped by responsibility.

`Notation.xcodeproj` defines the application target and shared schemes. Its navigator groups match the directories on disk.

- `Sources/`: application, browser, editor, model, storage, preferences, import/export, preview, UI, and utility code.
- `Resources/`: images, syntax queries, help, and interfaces. Localized resources live in `Resources/Localization/*.lproj/`.
- `Config/`: application plist, prefix header, and linker order files.
- `ThirdParty/`: bundled source dependencies, markup processors, and OpenSSL headers and libraries.
- `Scripts/`: development utilities.
- `Tests/` and `docs/`: test suites, review records, and documentation assets.

Read [architecture.md](architecture.md) before changing controller ownership, shared editing, or window lifecycle. Keep one shared library across browser windows. Keep the notes list above the editor. Add new source files and resources to the Xcode target.

## Build, Test, and Development Commands

Use macOS with full Xcode. The bundled MultiMarkdown executable and OpenSSL archive require an Intel build. Apple Silicon Macs require Rosetta.

Build the Development app:

```sh
xcodebuild -project Notation.xcodeproj -scheme 'Notation Develop' \
  -derivedDataPath build/DerivedData ARCHS=x86_64 \
  MACOSX_DEPLOYMENT_TARGET=10.13 CODE_SIGNING_ALLOWED=NO \
  GENERATE_PROFILING_CODE=NO OTHER_CFLAGS= WARNING_LDFLAGS= build
```

Run `open "build/DerivedData/Build/Products/Development/nvALT Development.app"` to open the app. Replace `build` with `analyze` for Clang static analysis.

## Coding Style & Naming Conventions

Match surrounding indentation, braces, and spacing. Avoid unrelated reformatting. Existing files mix tabs and four-space indentation.

Use PascalCase classes, matching header/implementation filenames, and camelCase selectors. Follow nearby category naming, such as `AppController_Importing.m`. Preserve manual `retain`/`release`/`autorelease` ownership. The repository has no standard formatter or linter.

## Testing Guidelines

After a Development build, run these suites from an active desktop session:

```sh
python3 Tests/run-multiple-windows-tests.py
python3 Tests/run-regression-tests.py
```

The suites use temporary notes and a copied app. See [Tests/README.md](Tests/README.md) for focused checks. No coverage threshold is configured.

Use disposable notes for manual checks of affected preview and import/export paths.

For CI changes, run `python3 -B -m unittest discover -s Tests/CI -v`.
CI builds an unsigned Intel app and tags successful builds on `master`. It does not run the desktop suites.
See [Tests/CI/README.md](Tests/CI/README.md) for artifact and tag rules.

## Commit & Pull Request Guidelines

History uses short descriptive subjects, often imperative, without a fixed prefix convention.

Keep commits focused. Explain the problem and resulting behavior in PRs. Link relevant issues. Report macOS/Xcode versions and test results. Include screenshots for UI changes. Exclude API keys, build products, and personal Xcode state.

## Documentation & Agent Guidance

Use direct, evidence-backed language. Avoid unearned qualifiers in documentation and responses.
Document ownership or data-flow changes in [architecture.md](architecture.md).
