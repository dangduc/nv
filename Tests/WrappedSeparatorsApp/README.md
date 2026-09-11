# Wrapped separators in the application

From an active desktop session, run:

```sh
python3 Tests/WrappedSeparatorsApp/run.py
```

For compilation without an app launch, run:

```sh
python3 Tests/WrappedSeparatorsApp/run.py --compile-only
```

The default app is `build/DerivedData/Build/Products/Development/nvALT Development.app`.
The `--app` argument selects another app. The `--output` argument selects another output directory.

The runner copies the app and uses disposable notes, a unique preference domain, isolated support files, and a private pasteboard.
It acquires the shared `build/pr-review/gui.lock` from the main checkout before app startup.
It does not open user notes or change the user's clipboard.

The suite exercises the actual source editor, production glyph delegate, and production typesetter.
It calibrates a native window to fit a 48-character Menlo word with insufficient room for its following space.
A single separator must leave the next word flush left after the automatic wrap.
A wider peer must display the same separator at its ordinary inline width.

The checks cover:

- Native Space input and shared Undo/Redo between single and double separator spaces.
- Native typing and shared Undo/Redo between trailing spaces and separators.
- Exact source preservation through native copy and paste on a private pasteboard.
- Independent shared-window layouts and note reattachment.
- Literal repeated spaces, trailing spaces, all-space source, real-newline indentation, tabs, and nonbreaking spaces.

The copy fixture uses the editor's advertised writable pasteboard types, then reads its plain-text representation.
Forcing only `NSPasteboardTypeString` caused the initial copy fixture to return failure on this host.

The runner writes these artifacts to `build/WrappedSeparatorsApp/`:

- `result.json`: app hash, exit status, assertion count, and failures.
- `observations.json`: compact native line fragments for the illustrative cases.
- `app.log`: assertion output.
- `wrapped-separators.png`: a native bitmap of the actual app window with synthetic source.

The first completed run passed all 32 checks on macOS 26.5.2 with Xcode 26.6.
The Intel app hash was `f1918d1d728fe257fe76368cebaadee2625ac3bc8688ab7c3b3cef977ec22384`.
The screenshot shows automatic wraps at the text margin and preserves the explicit leading space after a real newline.

This suite uses one font and two calibrated widths for the boundary case.
It does not establish all Unicode line-break behavior or behavior on another macOS release.
The screenshot uses native AppKit drawing. It does not inspect the final display compositor or simulate a physical resize drag.
