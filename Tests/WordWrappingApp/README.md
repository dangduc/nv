# Source word wrapping in the application

Run these checks after a Development build from an active macOS desktop session:

```sh
python3 Tests/WordWrappingApp/run.py
```

Use `--app /absolute/path/nvALT.app` to select another build.
Use `--compile-only` to compile the checks without starting an application.

The runner copies the app and gives it a unique preference domain.
It uses a temporary library, application support directory, and private pasteboard.
It acquires the shared `build/pr-review/gui.lock` in the main checkout before it starts the copied app.
It does not open the user's notes or change the user's clipboard.

The checks exercise the production typesetter and glyph delegate through the actual source editor.
They cover fitting prose words with three font and width combinations in plain text, Markdown, HTML, and JSON source modes.
Repeated Space events must preserve existing letter positions and advance the native caret across visual lines.
The observations include the caret geometry after 39 and 40 spaces follow `alpha beta`.

Two browser windows must share the note storage and own separate typesetters.
Their line breaks must remain independent during note switches, resizing, paste, Undo, Redo, and source syntax changes.
Layout must preserve source attributes, source generation, modification time, dirty state, selections, and Undo availability.
The suite also checks that keyboard commands and caret drawing retain the native `NSTextView` implementations.

Results are written to `build/WordWrappingApp/`:

- `result.json` records the app binary hash, exit status, and assertion count.
- `observations.json` records native line fragments and Space threshold geometry.
- `app.log` contains the assertion output.
- `word-wrapping.png` captures the actual app window with disposable prose.

The bitmap uses native AppKit view drawing. It does not test the final display compositor or a physical divider drag.
The checks do not establish every Unicode line-breaking rule or compatibility with an untested macOS release.

## Initial integration result

On 2026-09-11, the copied Intel app passed all 1,305 assertions on macOS 26.5.2 with Xcode 26.6.
The app binary SHA-256 was `10d1c49332562935a883e9c16d8e58adb4d67cc833bc34e066b4082db898de95`.
The suite delivered 402 Space events to the actual source editor.

With Menlo 18 and a 560-point window, the caret moved from `(544.01, 8)` after 39 appended spaces to `(23.84, 29)` after 40.
Every letter in the preceding `alpha beta` remained at its original position.
The second repeat fixture used Helvetica 19 and crossed two visual line boundaries without moving the prefix.

The generated screenshot was inspected and showed complete prose words at each visual line boundary.
macOS 13.7.8 still requires validation on the user's host.
