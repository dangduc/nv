# Repository Guidelines

## Project Structure & Module Organization

nvALT is a macOS Cocoa application written primarily in Objective-C, with C utilities. Most `.h`, `.m`, and `.c` files live at the repository root. `NVApplicationController` owns the shared library; `AppController` and `NVBrowserSession` manage each browser; `NotationController` and `NoteObject` manage notes; `LinkingEditor` handles editing; `PreviewController` handles markup previews.

`Notation.xcodeproj` defines the application target and shared schemes. Localized interfaces, strings, and help files live in `*.lproj/`; images live in `Images/` and the root. Supporting code includes `PTHotKeys/`, `RBSplitView/`, `JSON/`, `ODBEditor/`, `readability/`, and `Textile_2.12/`. Add new source files and resources to the appropriate Xcode target.

## Build, Test, and Development Commands

Use macOS with full Xcode; Command Line Tools alone are insufficient. Before the first build, create the ignored local configuration header:

```sh
cp SimperiumConfig-example.h SimperiumConfig.h
```

Keep the placeholder for local work without sync; Simplenote syncing requires your own API key.

```sh
open Notation.xcodeproj
xcodebuild -project Notation.xcodeproj -scheme "Notation Develop" build
xcodebuild -project Notation.xcodeproj -scheme "Notation Release" build
```

These open Xcode, build the `Development` configuration, and build `ForBuilding`, respectively. Run locally using the **Notation Develop** scheme and **Product > Run**. Replace `build` with `analyze` for Clang static analysis. The project contains legacy SDK, signing, and OpenSSL settings; document any toolchain adjustments needed to build.

## Coding Style & Naming Conventions

Match surrounding indentation: existing files mix tabs and four-space indentation. Preserve local brace and spacing conventions; avoid unrelated reformatting. Use PascalCase class names, matching header/implementation filenames, and descriptive camelCase selectors. Follow nearby category naming, such as `AppController_Importing.m`. Preserve manual `retain`/`release`/`autorelease` ownership. No repository-wide formatter or linter configuration is provided.

## Testing Guidelines

Run `python3 Tests/run-multiple-windows-tests.py` and `python3 Tests/run-regression-tests.py` after a Development build into `build/DerivedData`. See `Tests/README.md` for compatible build commands. The Cocoa integration suite uses temporary notes and a copied app. No coverage threshold is configured. Manually check affected preview, import/export, and sync paths with disposable notes. Record results in the PR.

## Commit & Pull Request Guidelines

History uses short descriptive subjects, often imperative, such as `Update project format`; no fixed prefix convention is evident. Keep commits focused. PRs should explain the problem and resulting behavior, link relevant issues, report macOS/Xcode versions and verification, and include screenshots for UI changes. Exclude API keys, build products, and personal Xcode state.

## Documentation & Agent Guidance

Use direct, evidence-backed language. Avoid unearned qualifiers in documentation and responses.
