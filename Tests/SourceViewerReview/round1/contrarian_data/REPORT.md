# Round 1: user-data and compatibility skeptic

Review baseline: `5e44a909bd6b7b2ad1957c475f94594e0bffd461`, PR #4.
This contrarian perspective challenges preservation claims and checks upgrade behavior. It accepts the removal of rich-text support.

## Confirmed finding

**[P2] Preserve the established fallback for unmarked MacRoman text**

Location: `Sources/Model/NoteObject.m:104` (called by `Sources/ImportExport/AlienNoteImporter.m:258–264`).

When a plain-text file has no BOM or `com.apple.TextEncoding` attribute and contains MacRoman characters, the new decoder tries Windows-1252 before MacRoman. Windows-1252 accepts the fixture bytes, so MacRoman is never tried. Importing `  café £ –\r\n` now produces `  cafŽ £ Ð\r\n`. The previous importer decoder returns the intended characters from the same file. This changes visible source characters for an existing supported input without a prompt. The unchanged export still returns the original bytes, which can conceal the decoding error in byte-round-trip tests.

Preserve the previous MacRoman fallback for ambiguous unmarked files, or require an explicit encoding choice. Continue to honor BOMs and recorded encoding metadata.

Evidence: `python3 Tests/SourceViewerReview/round1/contrarian_data/run.py` completed with 13 checks. `output.log` records the expected and actual UTF-8 bytes and detected encodings (previous: 30/MacRoman; current: 12/Windows-1252). The probe calls the production importer and the unchanged legacy decoder as a control in a copied app with disposable notes and preferences.

## Rejected concerns and limits

- Explicit MacRoman encoding attributes are honored. The same fixture imports correctly when tagged.
- Untagged valid UTF-8 source imports correctly.
- A UTF-16 BOM overrides an incompatible encoding hint correctly.
- Original bytes remain available for unchanged export. The finding concerns incorrect source characters, not an immediate rewrite of the imported file.
- The old decoder also cannot infer arbitrary unmarked encodings. This finding asks to preserve established behavior, not to solve universal encoding detection.
- Reviewed local syntax metadata storage and archive keys. Syntax stays in library preferences, while original bytes stay in the note archive. Existing focused tests cover sync payload exclusion and metadata restoration; no additional finding was established here.
- The first sandboxed desktop run exited without app output. The approved copied-app run completed. No real notes, defaults, external editors, or sync services were used.
- This run used macOS 26.5.2. It does not establish runtime behavior on macOS 10.13.
