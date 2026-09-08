# Round 3: user-data and compatibility skeptic

PR #4. Review baseline: `9720676ccd0e619dba99f6a47d257216c1e383eb`, with the two posted Round 3 fixes in progress.
This review accepts the removal of rich-text support. It does not repeat the signed-encoding or pending-capture findings.

## Result

No new actionable defect appeared in this bounded probe.
The production editing session passed 95 checks across seven source histories.
Each history used two layout managers, two source edits, five syntax changes, four Undo operations, and two Redo operations.

The first edit deliberately changed one newline boundary. The second edit appended text and another CRLF boundary.
The probe then changed syntax through JSON, HTML, Textile, Plain Text, and Markdown.
Undo restored the two source edits in order. Complete Undo restored the exact imported bytes, including each BOM.
Redo restored the edited bytes without normalization of untouched text. Syntax remained Markdown throughout Undo and Redo.

The final archive round trip retained original source bytes and local syntax through the note UUID.
Removal of both layout managers and closure of the editing session also retained the original bytes.

## Evidence

```sh
python3 Tests/SourceViewerReview/round3/contrarian_data/run.py
NV_REVIEW_MUTATE_UNDO_LINE_ENDINGS=1 python3 Tests/SourceViewerReview/round3/contrarian_data/run.py
```

The normal run returned 0. `output.txt` records all 95 successful checks.
The control returned 1 at the first Undo assertion. `negative-control.txt` records that expected failure.
The control replaces CRLF with LF only at the production Undo restoration boundary.
Thus the assertions detect an unwanted source transformation after successful import, edits, and syntax changes.

| Fixture | Encoding | Source boundaries |
| --- | --- | --- |
| Unicode without BOM | UTF-8 | CRLF, CR, LF, combining mark, precomposed character, emoji, ZWJ, Unicode line and paragraph separators |
| Unicode with BOM | UTF-8 | Same Unicode source |
| Unicode with BOM | UTF-16 LE | Same Unicode source |
| Unicode with BOM | UTF-32 BE | Same Unicode source |
| Legacy text | CP-1252 | Accents, currency, dash, CRLF, CR, LF |
| Whitespace only | UTF-8 | Space, tab, CRLF |
| BOM only | UTF-8 | Empty source |

The probe calls the production importer, source serializer, editing session, Undo manager, and note and preferences archive methods.
The runner copies the built app and uses disposable notes and a unique preferences domain.
It holds `build/pr-review/gui.lock` for the copied-app run.
The first sandboxed attempt exited before app output. The approved copied-app run completed.

## Limits

- The run used macOS 26.5.2 under Rosetta. It does not establish macOS 10.13 behavior.
- The two layout managers used native TextKit containers. The probe changed shared storage directly through production session commits.
- It does not measure visible highlighting completion, keyboard input, marked-text composition, or browser Preview transitions.
- The archive check uses keyed archive data in memory. Existing regression suites cover library files, encryption, and reopen behavior.
- No external editor, live Simplenote account, or real user notes participated.
- The control changes only the copied process. No production source changed during this review.
