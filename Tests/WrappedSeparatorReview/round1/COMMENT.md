Round 1 reviewed production commit `9e6c8dd6adc058e7044f2c562532af97dd4e63d4` against `75d6f42`. The later `d5232b4` commit adds tests and documentation only.

These are six subagent engineering perspectives, not reviews by the named people. Each reviewer wrote and ran new code. No actionable finding required a production correction in this round.

- **John Ousterhout:** 36 cached-versus-fresh production layout comparisons per architecture passed. Shared storage, separate layouts, attributed edits, combining characters, note detachment, and empty-note reuse preserved ownership and source data.
- **Dan Luu:** 44,158 checks passed in an Intel layout benchmark. Short-note initial layout added 0.014–0.017 ms. For 32,830 UTF-16 units, initial layout changed from 7.056 to 8.202 ms; an insertion/deletion pair changed from 7.093 to 8.210 ms. Initial explicit property-buffer allocations fell from 32 to zero. This measures layout cost, not application input latency.
- **Linus Torvalds:** 16,419 assertions per architecture passed. Evidence covers 1,936 callback cases, 16 allocation failures, native font fallback, buffer ownership, glyph indexes, and preservation of unrelated property bits.
- **Kyle Kingsbury:** 182 copied-app checks and 33 fresh-layout comparisons passed. Paragraph joins/splits, peer selections, Undo/Redo, copy, and save/reopen preserved the expected source and geometry.
- **Contrarian UX:** 1,642 assertions per architecture passed. Six collapsed-separator fixtures matched native word wrapping for movement, selection, caret affinity, and click targets. Marked-text API replacements preserved source and fresh-layout equality.
- **Contrarian platform compatibility:** 1,406 assertions and 18 paragraph/font/attachment comparisons per architecture passed. Strict API availability checks and Mach-O metadata confirmed the Intel 10.13 and arm64 11.0 deployment targets. Attachment-layout differences also occurred in the baseline and do not establish a regression in the plain-text editor.

The evidence runs on macOS 26.5.2 with Xcode 26.6. Intel code ran through Rosetta. It does not establish macOS 13.7.8 behavior, physical IME input, or compositor caret pixels.

Reports, probe code, results, and further limits: [Round 1 evidence](https://github.com/fastducduc/nv/tree/codex/collapse-wrapped-separators/Tests/WrappedSeparatorReview/round1).
