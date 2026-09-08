# Archived encoding identity correction

PR comment: https://github.com/fastducduc/nv/pull/4#discussion_r3956760257

`NoteObject` now compares the 32-bit encoding identifiers before it reuses original source bytes.
The comparison accepts the signed extension produced by the legacy archive field.
It still requires unchanged source characters and matching encoding identifiers.
The archive format stays compatible with existing note records.

The permanent storage suite adds a GB18030 fixture using the valid byte alias `A3 A0`.
Foundation decodes those bytes as U+3000 and normally encodes that character as `A1 A1`.
The fixture imports the tagged file, archives and restores the note, checks conflict-copy identity, and exports the recovered note.
Its source and exported bytes must remain `A3 A0`.

## Evidence

The new storage fixture failed against the app built from `9720676`.
The failure was `unchanged archived GB18030 source preserves its original byte alias`.
The original import, source-byte check, and restored encoding identity passed before that failure.

After the production change, `python3 Tests/SourceViewerReview/round3/linus/run.py` passed all 262 checks.
Its three negative controls still failed: double BOM consumption had 4 failures, missing conflict origin had 31, and retained cancellation had 4.
The historical baseline report and `output.txt` remain unchanged.

The combined Development build passed.
The actual-app storage suite passed all 243 checks, including the recovered GB18030 export.
The command was `python3 Tests/Regression/source-storage/run.py`.
Local output: `build/review-round3-storage.log`.
