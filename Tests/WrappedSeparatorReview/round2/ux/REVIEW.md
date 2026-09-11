# Round 2: deletion and replacement at the separator

No actionable interaction regression was found.
The frozen production revision is `2ea92180939a3e51df8fe867ad548140ed455868`, against `75d6f42`.

Both arm64 and x86_64 passed 164 assertions.
Each run covers eighteen edit cases and two trailing-to-separator transitions.
The fonts are Menlo and Helvetica at 18 points.
Every case begins with `abcdefghij nextword` at a width that collapses its single separator.

The new cases cover these operations:

- Backspace and Forward Delete on the separator.
- Backspace before the separator and Forward Delete at the wrapped word's start.
- Deletion of a selection that spans the separator.
- Word Backspace after the following word and at its start.
- Replacement of a selection across the wrap with Latin or Unicode text.

All edits produced the independently specified source and logical selection.
Source selections and insertion affinity matched native word wrapping.
All twenty edited snapshots matched fresh production layouts, including line rectangles and insertion positions.
Eighteen snapshots also matched native word-wrap geometry exactly.

Deleting `nextword` leaves an intentionally literal trailing space.
The probe checks its nonelastic glyph property, following-line placement, and one-space caret advancement.
It compares that state with fresh production geometry because native trailing-space collapse is outside the requested policy.
Inserting `newword` then restores the collapsed separator and native word-wrap geometry.

## Reproduction

```sh
python3 Tests/WrappedSeparatorReview/round2/ux/run.py
```

The runner extracts the actual hook and typesetter from the frozen commit.
It reuses only the round-one Cocoa setup and reference helpers.
The earlier interaction matrix does not run.
`results.json` contains compact per-edit source, selection, affinity, and line-range records.
The host was macOS 26.5.2.
Intel execution uses Rosetta and the macOS 10.13 deployment target.
The arm64 deployment target is macOS 11.

## Limits

These are headless `NSTextView` command and layout checks.
They do not cover key-event dispatch, painted caret pixels, physical input methods, or older macOS releases.
The probe does not exercise the application's shared Undo manager.
The root's copied-app checks cover basic Undo and copy/paste separately.
No windows, personal notes, preferences, keychain items, production files, commits, or PR comments changed.
