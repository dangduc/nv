# Source backspace regression

Build the Development app, then run:

```sh
python3 Tests/SourceBackspace/run.py
```

The runner copies the app and uses a disposable library and preferences domain.
Git worktrees share the main checkout's desktop-test lock.
The native process has a 150-second timeout. Results and its log go to `build/SourceBackspace`.
Use `--compile-only` to compile the injected fixture without launching the app.

The first case installs search backgrounds through the production editor API and caches a native bitmap.
It then deletes the final character of a 26-character source.
This setup reproduces the range exception in the old application.
It supplies the highlighting precondition directly; it does not claim to reproduce search-field input.
The probe never replaces editing, highlight cleanup, or drawing behavior.
Its startup hooks isolate application paths and suppress external-editor initialization.

Checks cover Plain Text, Org, Markdown, JSON, and HTML source modes.
They cover native ordinary deletion, indentation, newline, composed Unicode,
selected text, and the empty result.
Additional checks cover Undo, Redo, shared layouts, uncommitted composition, syntax colors, note switching, and pending cleanup during closure.
Native bitmap rendering runs before and after deletion and during composition.
A retained drawing dictionary checks immediate background suppression separately from later attribute removal.
The lifecycle fixture schedules cleanup through the production invalidation API before switching and closing windows.
Its exact query matches the old note's title and the new note's body.
The fixture checks that query and selection before it tests cleanup.

To check the original failure against an older built app:

```sh
python3 Tests/SourceBackspace/run.py --app /absolute/path/to/old/nvALT.app \
  --expect-original-crash --output build/SourceBackspaceNegativeControl
```

That mode requires the original index-25, length-25 range exception on the first deletion.
An unrelated exception, timeout, or successful deletion fails the negative control.

On macOS 26.5.2 with Xcode 26.6, the fixed Intel app passed 310 checks through Rosetta.
The same first-deletion fixture reproduced the range exception in the old app.
These runs do not establish behavior on the reported macOS 13.7.8 system.
