# Round 1 layout cost probe

This independent probe links the production `NVSourceTypesetter.m`.
It extracts the current glyph delegate from `LinkingEditor.m` without changing its implementation.
Both modes retain the source paragraph style and nonelastic-space policy.
The control omits the custom typesetter, matching the layout policy before PR 28.

Run from the worktree:

```sh
python3 Tests/WordWrapReview/round1/luu/run.py
python3 Tests/WordWrapReview/round1/luu/run.py --instrument
```

The runner uses Intel Cocoa text systems under Rosetta, with `-O1` and the macOS 10.13 deployment target.
It creates no windows and opens no note library. All layout operations run on the main thread.
Products and logs stay in `build/WordWrapReview/round1/luu`.
The two JSON files contain the recorded results.

The primary run excludes instrumentation. Each case uses one warmup followed by six samples per mode, with alternating mode order.
The separate instrumented run counts actual production Core Text and tokenizer calls. It supplies attribution, not benchmark timing.
Source construction occurs outside each interval. Timed intervals include the edit or resize and the requested native layout.
Postchecks inspect exact source contents and the completed layout range.

The fixtures contain 100 characters of short prose, then 4,050 to 524,250 characters in one paragraph.
The unit is `one two three four five six seven eight nine ten. `.
Two controls replace its final space with a newline, creating 50-character paragraphs in larger documents.
The font is Menlo 18. The initial container width is 544 points.

The four operations are initial layout of a 544-by-600-point viewport, eight beginning edits, eight end edits, and eight viewport resizes.
Beginning edits insert `k` at offset 32 and advance the insertion offset.
End edits insert `k` at the end after initial layout through the original caret position.
Resizes alternate between widths of 344 and 544 points. Both modes request only the first 600 points of layout height.
The native engine nevertheless lays out a complete long paragraph for the viewport request.

The probe does not dispatch key events through nvALT or measure display frames.
It does not include source analysis, autosave, search, scrolling, or physical input-method composition.
