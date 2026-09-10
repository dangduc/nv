# Round 1: contrarian UX and compatibility review

Reviewed `b3c2162b9adea5e1c2819f7372ff0f7e7986a64a` against `8dde5e8`.
This perspective challenges behavior changes caused by asynchronous analysis.

## P2: Preserve ordinary caret placement while link analysis is pending

Location: `Sources/Editor/LinkingEditor.m:454`.

When URL clicking is disabled, Cocoa still calls `clickedOnLink:atIndex:` for clicks inside attributed links.
The existing branch places the caret at the clicked character.
The new freshness guard returns before that branch.
Consequently, any source edit creates an interval when clicks inside existing URL text do nothing.
This occurs even when the edit does not change that URL.

The native probe creates a disposable note containing `https://example.com` followed by another line.
It disables URL clicking and sends mouse-down and mouse-up events through `NSApplication`.
A click inside the current URL moves the caret from the note's end to index 3.
After appending one character to the last line, the identical click leaves the caret at index 30.
Both clicks invoke the production link callback exactly once.
The stale click occurred before the fixed 60 ms analysis delay elapsed.

Preserve ordinary caret placement in this path while rejecting stale link targets.
The native regression should pass after that change.

## Evidence

Run `python3 Tests/TypingReview/round1/contrarian_ux/run.py` after building the Development app.
The runner copies the app and uses a temporary notes directory and unique preferences domain.
It does not modify the regular nvALT process or library.

`probe-body.m` and `support.h` exercise the compiled production editor, session, and browser.
The mouse-click recorder forwards to the unchanged production callback.
Only the later activation control intercepts Cocoa's final link-opening handler, to avoid opening a browser.

`output.txt` records 22 passing checks and the failing caret-placement assertion.
The same caret failure appeared in three completed variants of the probe.
The final variant also verifies:

- A stale context menu removes old URL attributes before Cocoa creates link actions.
- Pending analysis restores current link attributes after that menu cleanup.
- A changed URL cannot reach Cocoa's activation handler until analysis is current.
- The visible word count arrives asynchronously and changes correctly when switching notes.

Host: macOS 26.5.2, Intel app under Rosetta.
Tested binary SHA-256: `1d4ca5d7db470f261a7abf458952b526f7c3c8e548fdf33a86fa06e80f3485b0`.

The probe does not exercise an external edit while an existing context menu tracks.
It also does not verify the modifier timer that shows the temporary word-count popup.
No defect is claimed for those untested paths.
