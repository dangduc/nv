# Org preview UI checks

Build the Development app.
Then run:

```sh
python3 Tests/Regression/org-preview-ui/run.py
```

The runner copies the app and creates disposable notes and preferences.
Git worktrees use the main checkout's desktop-test lock.

The checks exercise native preview controls, menu validation, WebKit rendering, viewer restoration, source composition, and HTML export.
DOM checks cover headings, tasks, lists, tables, emphasis, links, and literal blocks.
Preview changes preserve source syntax, source characters, Undo, and the source caret.
Peer edits update the preview from the exact committed snapshot.
Code blocks create no output file, and include directives do not expose the referenced file's contents.

The heading-navigation check captures the native scroll position immediately after a real fragment link changes the document URL.
The periodic state timer stays inactive during this check.
A reply gate tests fragment, host, path, query, and scheme variants against the production capture method.
Checks also cover encoded hash characters, duplicate replies, and newer restoration state.

On macOS 11 or later, a forwarding probe checks that the native Find action reaches WebKit and reports a match.
The export probe supplies the save-panel destination and response. Production code captures the displayed result and writes the HTML file.
These checks do not cover physical keyboard input or external link activation.

Set `NV_UI_ARTIFACTS` to a directory to capture the native Org preview window without image edits.
The capture uses only disposable fixture notes.

On macOS 26.5.2 with Xcode 26.6, the suite passed 102 checks.
Screenshot capture adds three checks.
