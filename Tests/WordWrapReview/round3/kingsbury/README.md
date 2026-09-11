# Round 3: window closure and persistence

No actionable finding. Both app processes passed at frozen commit `63911bf2c66d438f178b43a8b9e996787e29acc9`.
The save process passed 41 checks. The reopen process passed 12 checks.
All eight layout comparisons matched fresh production layouts and found both paragraph-cache pointers empty.

This review uses a Kyle Kingsbury-inspired focus on histories and invariants. It does not represent Kyle Kingsbury.

## New histories

| History | Sequence | Observed result |
| --- | --- | --- |
| P1 | Append source from a peer editor, close that originating window, resize the survivor, then Undo and Redo. | The survivor restored exact source bytes in the editor and model. Shared history survived the originating window. |
| P2 | Resize and invalidate the full layout three times, flush the library, close its journal, exit, then reopen the library in another app process. | Layout preserved source, generation, modification time, and Undo availability. Reopen preserved exact UTF-8 source, note UUID, and title. |

The fixture includes Vietnamese text, Chinese text, a combining mark, an emoji sequence, a tab, paragraph separators, and 72 trailing spaces.
The comparison uses UTF-8 data equality for source and model assertions.
The expected source comes from the fixture operations, then passes to the second process through `expected.json`.

The runner copies the production app and uses disposable notes, an isolated preference domain, and private support and temporary directories.
The shared `build/pr-review/gui.lock` covers both processes. The runner released it after the second process exited.
All production files and earlier review rounds remained unchanged.

## Implementation and results

The new probe runs actual source-editor commands, note Undo and Redo, browser closure, library flush, and library startup.
It reuses the earlier fresh-layout comparison and direct cache-pointer reads.
This round does not replace or wrap any production method.

The fresh comparison uses the linked production typesetter and glyph delegate, with matching native attributes and container settings.
It compares line ranges, glyph ranges, line rectangles, used rectangles, glyph positions, and any extra line fragment.
Every line range must cover its source characters exactly once. Layout must preserve source attributes and selection.

- App SHA-256: `62c09640835e03f1fcf5bb559565f220801685c0f5241187f078943cf6fc5f8e`.
- macOS 26.5.2 (25F84), Xcode 26.6 (17F113), Intel app through Rosetta.
- 53 checks passed, eight layout comparisons passed, both process exit statuses were 0.
- `results.json` records both process results and production hashes before and after the run.
- `save.log` and `reopen.log` record the assertions from each process.
- `save-observations.json` and `reopen-observations.json` record the layout comparisons and cache state.
- `expected.json` records the disposable source, UUID, and title.

## Run

From the worktree root, run:

```sh
python3 Tests/WordWrapReview/round3/kingsbury/run.py
```

For compilation without an app launch, run:

```sh
python3 Tests/WordWrapReview/round3/kingsbury/run.py --compile-only
```

The `--app` argument accepts another absolute app path.
The app run requires an active desktop session. Compilation produced no diagnostics.

## Limits

This run covers a successful flush and reopen. It does not cover crashes, interrupted writes, encrypted storage, or export.
The checks do not require Undo history to persist across app processes.
Fresh-layout equality cannot expose deterministic layout errors that affect both compared layouts equally.
The cache assertions inspect two typesetter pointers. They do not measure total memory.
The resize uses native window sizing, without a physical drag or compositor inspection.
This run does not establish behavior on macOS 13.7.8.
