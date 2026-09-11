# Round 2: paragraph cleanup across lifecycle histories

No actionable finding. All 96 checks passed at corrected commit `4c8f6b449504a50caa460d78efebd42b94beaba6`.
All 18 observed layouts matched fresh production layouts and retained neither paragraph analysis cache.
The production files remained unchanged. Round 1 artifacts remain separate and unchanged.

This review uses a Kyle Kingsbury-inspired focus on histories and invariants. It does not represent Kyle Kingsbury.

## New evidence

These two histories target the new `endParagraph` cleanup boundary.
They run through actual browser windows, shared editing sessions, and the linked production typesetter in a copied app.
The runner and fresh-layout comparison reuse the Round 1 infrastructure. The lifecycle histories and cache observation are new.

| History | Sequence | Required result |
| --- | --- | --- |
| L1 | Lay out three paragraphs in two windows, delete all source, restore it through peer Undo, delete the selected note, then select another note. | Empty editors retain no previous analysis. Note deletion detaches both browsers. All 10 layout comparisons preserve source attributes and selection. |
| L2 | Compose local replacement text, receive a nonoverlapping external model replacement, close the peer, resize, commit the merge, then Undo and Redo. | Peer closure preserves composition. Commit preserves local and external changes. Undo removes only the local change. All eight layout comparisons preserve source attributes and selection. |

The probe observes `endParagraph` through a wrapper that forwards every call to the original production method.
The wrapper reads the `paragraphMeasure` and `lineBreaks` pointers before and after that call.
It neither invokes layout nor releases or resets any cache.
Only the two actual editor typesetters contribute to these counters. Fresh comparison objects do not contribute.

The run observed 50 paragraph completions with allocated measurements and 47 completions with allocated break tables.
After all 50 original completion calls, both cache pointers were null.
The observation therefore checks cleanup of populated caches, rather than only the initial empty state.

Each layout comparison checks line ranges, glyph ranges, line rectangles, used rectangles, glyph positions, and any extra line fragment.
Line ranges must cover every source character exactly once.
The fresh comparison uses the linked production typesetter and glyph delegate, with copied attributes and matching native text settings.
It contains no replacement word-break algorithm.

## Run and artifacts

From the worktree root, run:

```sh
python3 Tests/WordWrapReview/round2/kingsbury/run.py
```

For compilation without an app launch, run:

```sh
python3 Tests/WordWrapReview/round2/kingsbury/run.py --compile-only
```

The `--app` argument accepts another absolute app path.
The runner requires an active desktop session and uses the main checkout's `build/pr-review/gui.lock`.
It copies the app and uses disposable notes, a private preference domain, and isolated support and temporary directories.

- `results.json`: commit, app hash, environment, assertion count, and production hashes before and after the run.
- `observations.json`: all 18 checkpoint layouts, cache states, and completion counters.
- `app.log`: all assertions and the final completion counters.
- `compile.log`: empty, because compilation produced no diagnostics.

The recorded app ran through Rosetta on macOS 26.5.2 (25F84), with Xcode 26.6 (17F113).
Its SHA-256 was `62c09640835e03f1fcf5bb559565f220801685c0f5241187f078943cf6fc5f8e`.
The process exit status was 0.

## Limits

The cache counters describe the actual editor typesetters in these two histories. They do not measure total process memory or all TextKit caches.
Fresh-layout equality cannot expose deterministic errors that affect both layouts equally.
These histories do not measure long-paragraph performance, uncommon paragraph styles, or RTL alignment.
The composition uses native marked-text APIs, without a physical input method or candidate window.
The external replacement enters through the actual note model, without a sync transport.
The resize uses AppKit window sizing, without a physical divider drag or compositor inspection.
This run does not establish behavior on macOS 13.7.8.
