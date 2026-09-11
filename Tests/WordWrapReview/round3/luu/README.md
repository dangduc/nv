# Round 3 space and token layout cost

The runner links the frozen production typesetter from `63911bf2c66d438f178b43a8b9e996787e29acc9`.
The control uses native character wrapping without that typesetter, matching the layout policy at base `b6a5696`.
The runner extracts the production space glyph delegate and asserts that both revisions contain the same method.

Run from the worktree:

```sh
python3 Tests/WordWrapReview/round3/luu/run.py
python3 Tests/WordWrapReview/round3/luu/run.py --instrument
```

Each fixture contains 32,768 characters: ordinary spaces or one unbroken token made from `k` characters.
Both modes use a native `NSTextView`, Menlo 18, and character paragraph wrapping.
The text views remain windowless and use disposable text storage.
No application preferences or note libraries are opened.

Each case uses one warmup and six measured samples per mode, with alternating mode order.
The three operations are eight width changes, 64 end edits, and 256 repeated viewport and caret queries.
Widths alternate between 344 and 544 points. End edits append 32 characters through `insertText:`, then remove them through native Backspace.
Each resize and edit asks for the insertion point at the source end, which requires layout through that location.
The repeated-query case uses a 544-by-600-point viewport and the already laid-out end position.

The probe obtains native insertion points through `getLineFragmentInsertionPointsForCharacterAtIndex:`.
Every query asserts that the text view's selection remains at the expected source end.
Paired modes must produce identical insertion-point histories, final insertion points, and line counts.
Each case must restore the exact initial source and selection.

Source setup occurs outside the timed interval. The interval includes native editing or resizing, layout, insertion-point queries, and history collection.
Both modes perform the same collection work. The separate call-count run is excluded from timing conclusions.
The counters wrap calls in the actual production implementation, without copying its algorithm.

The runner builds Intel code with `-O1` and the macOS 10.13 deployment target.
Products and logs stay in `build/WordWrapReview/round3/luu`.
The committed JSON files contain recorded measurements and insertion-point histories.
