# Round 1: composition and shared-state histories

This review uses a perspective inspired by Kyle Kingsbury. It does not represent his review or endorsement.

Reviewed commit: `83a7307`, against base `f772c4b`.
Environment: macOS 26.5.2 (25F84), Xcode 26.6 (17F113), Intel apps under Rosetta.

No actionable finding emerged from the tested composition histories.

## New evidence

The probe runs eight histories in actual copied nvALT apps: four event orders with Plain Text and Markdown syntax.
Both apps use temporary notes, unique preference domains, and the shared GUI lock.
The candidate executes the production glyph method through an observer that forwards the original implementation.
The observer counts calls and does not change glyph arguments or results.

The histories interleave native `setMarkedText:selectedRange:replacementRange:` calls with these events:

- Forced glyph regeneration in both shared editors.
- Different window widths and width changes while composition remains active.
- Replacement of the marked candidate with Vietnamese text and a long space run.
- A deferred external suffix update, composition commit, merged content, shared Undo, and Redo.
- Undo from the peer while the first editor still has marked text.
- A peer note switch and reattachment while the first editor continues composition.
- A note switch by the composition owner, followed by Undo in the remaining peer and Redo after reattachment.

Each recorded state checks the exact live source and committed model source.
It checks shared storage identity, peer text, bounded selections, and marked-text state.
Forced glyph regeneration also checks complete source attributes, source generation, both selections, both marked ranges, and Undo availability.

The candidate passes 492 checks. The baseline passes 490 checks.
The two extra candidate checks cover the production method and callback execution during composition.
Every recorded source, model, selection, and composition state matches between the candidate and baseline.
The geometry control differs as expected: 201 spaces wrap in the candidate and occupy one line in the baseline.

## Reproduction and limits

Run `python3 Tests/WhitespaceWrapReview/round1/kingsbury/run.py` from the worktree with desktop access.

The script writes the complete comparison to `results.json`.
Build products, generated source, separate app results, and logs remain under ignored `build/WhitespaceWrapReview/round1/kingsbury`.
The JSON check counter precedes the final successful evidence-write check.

These are serialized event histories on the AppKit main thread, with normal asynchronous analysis allowed between events.
The test exercises native marked-text APIs, rather than a physical keyboard or installed input-method candidate window.
It does not prove every input method, every composition cancellation path, macOS 13 behavior, or simultaneous external-file writes.
The probe closes the peer after the histories; it does not test window closure during active composition.
