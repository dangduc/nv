# Round 1: interface and ownership review

Perspective: John Ousterhout-inspired review of abstraction boundaries. This is not a review by, or endorsement from, John Ousterhout.

No actionable finding in the reviewed change.

The browser still invalidates request generations immediately at `AppController_Search.m:155`. The editor now owns the separate display-invalid state and deferred attribute cleanup. That boundary avoids requiring the browser to know when TextKit has adjusted its glyph ranges. `setSearchHighlightRanges:` cancels cleanup before installing a current result, and the existing note-attachment sequence calls cleanup before moving the layout manager.

## Executable evidence

Run `python3 Tests/SourceBackspaceReview/round1/ousterhout/run.py` from the repository root.

The script extracts the exact four production methods from `LinkingEditor.m`, compiles an Intel Objective-C probe, and executes it through Rosetta. The adapter uses actual `NSTextStorage`, `NSLayoutManager`, temporary attributes, notifications, and delayed selectors. It creates no window or copied application.

Result: **23 checks, zero failures**, on macOS 26.5.2. The compiler emitted no warnings.

- Character notifications mark backgrounds stale before any cleanup touches layout. The delegate removes the stale background from returned display attributes and retains the foreground attribute.
- Cleanup removes only the search background and leaves temporary foreground attributes intact.
- A new highlight arriving before a queued cleanup cancels that callback and survives the next run-loop turn.
- Two nested storage edit transactions remain open across run-loop turns. Cleanup retries without mutating layout while either transaction remains open, then completes after the outer transaction ends.
- The production cleanup/detach/attach sequence cancels an old note's callback. A new note's highlight survives subsequent run-loop processing.
- Releasing an editor with a pending delayed selector does not leak it after cleanup finishes. The probe records two expected deallocations.

`manifest.json` records the full upstream base, four reviewed production file SHA-256 hashes, extracted selectors, generated probe hash, platform, and exit code. All four production files were unchanged across the probe. `output.txt` contains the compact result; `compile.txt` is empty on success.

## Limits

This adapter does not instantiate the full `LinkingEditor`, browser, source analyzer, or window. It verifies the changed cleanup and ownership contracts against real AppKit objects. The suppression assertion enters the exact display delegate with `forDrawingToScreen:NO`; it does not test syntax coloring or marked text. Full-app keyboard, shared-window, and macOS 13.7.8 reproduction remain separate checks.

The nested edit test verifies safety and eventual cleanup. It does not claim a latency bound while an edit transaction is held open.
