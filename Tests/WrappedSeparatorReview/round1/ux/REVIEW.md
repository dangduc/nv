# Round 1: collapsed-separator interaction review

No actionable interaction regression was found in these bounded cases.
This review covers PR 30 at `9e6c8dd6adc058e7044f2c562532af97dd4e63d4`, against `75d6f42`.

The first hypothesis was that a collapsed separator creates inconsistent caret positions, selections, or click targets.
Six fixtures place a single separator immediately after a nearly full visual line.
The fonts are Menlo and Helvetica at 18 points.
The source includes ordinary Latin text, accented text, and a composed emoji.

All six production layouts matched native word-wrap line ranges and rectangles.
The 576 command comparisons matched native source selections and insertion affinity.
Commands cover arrows, selection extension, word movement, and line and paragraph endpoints.
The 378 point samples include both sides of insertion positions, exact insertion positions, and both line margins.
All click targets matched the native reference.
Sixty range comparisons covered word/paragraph granularity and selection rectangles around the separator.

The separator retains a logical source position despite its reduced visible width.
For example, the Menlo fixture leaves 0.25 points for the separator after `abcdefghij`.
Source index 11 appears at both the preceding line's endpoint and the next line's start.
Native insertion affinity resolves that shared soft-wrap index identically in both editors.
The test does not require every source space to retain a full visible cell.

The second hypothesis was that marked replacement beside the separator leaves stale source ranges or caret geometry.
Eight marked-text steps replace the following word with Latin text, a combining sequence, CJK text, and an emoji sequence.
All source strings, marked ranges, and selections match the intended replacements.
Every resulting layout and native insertion position matches a fresh production layout.
Unmarking ends composition in both font cases.

## Reproduction

```sh
python3 Tests/WrappedSeparatorReview/round1/ux/run.py
```

Both arm64 and x86_64 passed 1,642 assertions on macOS 26.5.2.
Intel execution uses Rosetta and the macOS 10.13 deployment target.
The arm64 deployment target is macOS 11.
`results.json` records counters and production source hashes.
The two geometry files retain the six production/reference observations.
Both architectures produced identical normalized geometry observations.

The runner extracts the exact glyph hook and typesetter sources from the frozen commit through `git show`.
The probe reuses the earlier Cocoa text-system helpers, but does not run their word-wrap matrix.
The native reference uses ordinary `NSTextView` word wrapping without the custom typesetter or glyph delegate.
The comparison does not reproduce the separator-classification algorithm.

## Limits

This is a headless native text-view check.
It does not cover painted caret pixels, physical mouse input, key-event dispatch, an actual input method, or older macOS releases.
Marked-text API calls do not establish end-to-end input-method behavior.
The probe does not repeat the root's copied-app Undo and pasteboard checks.
Repeated spaces, indentation, and trailing spaces remain outside this single-separator interaction hypothesis.
No windows, personal notes, preferences, keychain items, production files, commits, or PR comments changed.
