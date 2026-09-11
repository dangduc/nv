# Round 2: Unicode composition and history

This review uses a perspective inspired by Kyle Kingsbury. It does not represent his review or endorsement.

Reviewed head: `072a6bc0f54a52603f8cedfbcacc17d0ab836a36`.
The runner checks candidate binary SHA-256 `be02dd1fe33a39c74b8961441be55f4f91378d46935bdba99fd610d405c3e09b`.
Environment: macOS 26.5.2 (25F84), Xcode 26.6 (17F113), Intel apps under Rosetta.

No actionable finding emerged from these histories.

## New evidence

Eight histories exercise the final character-wrapping policy in actual copied apps.
Four operation orders run with Plain Text and Markdown syntax at Menlo 18.
The source contains a newline, 120 spaces after `alpha beta`, Vietnamese text, and a combining accent.
The two shared editors have different widths.

Each history replaces the final source word with three successive marked-text candidates.
The candidates contain combining text, Vietnamese text, 80 spaces, and a joined emoji with a skin-tone modifier.
The probe regenerates both editors' glyphs after each candidate replacement.
It checks the complete shared attributes, source generation, selections, marked ranges, committed model, and Undo availability.
It also checks that composition retains the expected paragraph policy.

The new operations include:

- Commit through native `insertText:replacementRange:` after marked-text replacements.
- A deferred external prefix before the local composition range, followed by a correct merge.
- Shared Undo while both native composition and the external prefix remain pending.
- A peer note switch and reattachment during Unicode composition.
- Native Backspace over the final joined emoji, followed by peer Undo and Redo.
- Undo from the remaining peer after the composition owner switches notes.

Backspace removes exactly the final composed-character sequence.
The logical caret follows that deletion, and shared Undo restores the complete sequence.
The separate note remains unchanged during detach and reattachment.

The candidate passes 974 checks; the baseline passes 972 checks.
The two extra candidate checks cover the production glyph method and its execution during composition.
Every recorded live source, committed model, selection, and composition state matches the baseline exactly.
The geometry control confirms that only the candidate wraps the 201-space control onto multiple lines.

## Reproduction and limits

Run `python3 Tests/WhitespaceWrapReview/round2/kingsbury/run.py` from the worktree with desktop access.

The runner uses the shared GUI lock, copied apps, disposable notes, and unique preference domains.
The common harness and invariant helpers come from round 1; the history body contains the new operations described here.
`results.json` contains complete state histories and glyph callback counts.
Logs and build products remain under ignored `build/WhitespaceWrapReview/round2/kingsbury`.
The recorded check counter precedes the final successful evidence-write check.

These tests use native marked-text APIs without a physical keyboard or an installed input-method candidate window.
The operations are serialized on the AppKit main thread, with normal asynchronous analysis between operations.
They do not cover every input method, overlapping external conflicts, active-composition window closure, or macOS 13 behavior.
