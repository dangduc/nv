Round 2 reviewed `2ea92180939a3e51df8fe867ad548140ed455868`. Production was unchanged from round one. All six reviewers wrote and ran new probes.

**P3 performance finding:** Separators with strictly printable ASCII neighbors need not query their composed-character range. A 256K-paragraph start-edit pair took 113.411 ms in the base and 131.697 ms in the candidate. Both generated the same glyphs. A separate instrumented experiment saved 9.432 ms with an ASCII shortcut and passed 14 mixed/composed controls. This is layout evidence, not full-app typing latency. The correction will retain the complete composed-character check for every non-ASCII neighbor and will be validated before round three.

- **John Ousterhout:** 2,670 assertions and 162 fresh-layout comparisons per architecture passed across all six request orders for three shared layouts. Targeted invalidation, note exchange, metric changes, and paragraph-cache release remained local to each layout.
- **Dan Luu:** Identified the P3 recommendation above. Long paragraphs already require broad regeneration for edits near the start; the new code did not amplify that work. Short-paragraph edits remained local. The [report](https://github.com/fastducduc/nv/blob/codex/collapse-wrapped-separators/Tests/WrappedSeparatorReview/round2/luu/REVIEW.md) separates baseline timing from the shortcut experiment.
- **Linus Torvalds:** 6,703 assertions per architecture passed across 86 Unicode-neighbor cases and 258 edit phases. Cached glyphs matched fresh production; mappings, bidi levels, attributes, and source were preserved.
- **Kyle Kingsbury:** 117 actual-app assertions passed across 36 seeded edit/Undo/Redo commands and 74 fresh-layout comparisons in two shared editors.
- **Contrarian UX:** 164 assertions per architecture passed for deletion, replacement, native caret affinity, and trailing-space-to-separator transitions.
- **Contrarian platform compatibility:** 252 assertions per architecture passed across ten metric/hard-break cases. CRLF, CR, LF, U+2028, U+2029, and their indentation remained intact.

No other actionable findings arose. The named lenses are subagent engineering perspectives, not reviews by those people. Runtime coverage remains macOS 26.5.2; older macOS, physical input methods, and final compositor pixels remain outside these probes.

[Round 2 reports, executable probes, results, and limits](https://github.com/fastducduc/nv/tree/codex/collapse-wrapped-separators/Tests/WrappedSeparatorReview/round2).
