# Round 1: durability and concurrent histories

Perspective: Kyle Kingsbury-inspired review. This is an engineering lens, not a statement from Kyle Kingsbury.

Reviewed commit: `5e44a909bd6b7b2ad1957c475f94594e0bffd461` (PR #4).

## Evidence

Run from the repository root in an active macOS desktop session:

```sh
python3 Tests/SourceViewerReview/round1/kingsbury/run.py
```

The runner compiles an injected Objective-C probe, copies the Development app, and uses disposable notes and preferences. It takes `build/pr-review/gui.lock`. The probe replaces only conversion-alert presentation with a counter to model pressing Cancel. File imports, model edits, source writes, directory reconciliation, encoding decisions, conversion, and archive reads use production code. `output.log` records the run: 24 checks completed, two canceled conversion offers.

The checks labeled `REPRO` assert the current bug. They are review evidence, not passing correctness expectations.

## K1 — P1: preserve external content while conversion is pending

PR anchor: `Sources/Storage/NotationDirectoryManager.m:365`.

A canceled conversion creates a persistent divergence between the note archive and its source file. The new `sourceConversionPending` condition discards every subsequent external file update from reconciliation, without preserving a conflict copy. Later `upgradeEncodingToUTF8` writes the local body over that external content.

Observed history:

1. Import a CP-1252 file containing `seed café` and flush.
2. Append `local 😀`, then cancel the required UTF-8 conversion. The archive retains the local edit; the file retains the seed.
3. Write `external durable update` through an external file operation. Reconcile the directory.
4. Accept UTF-8 conversion and flush.

Output: `externalOnDisk=0 conflictPreserved=0 noteCount=1`. The external edit existed on disk before conversion. After conversion, neither the file nor any note contains it. A mere file metadata update must still leave pending source intact; a changed body needs conflict preservation or an explicit resolution before replacement. Preserve both source versions when reconciliation detects this case, and recheck before the delayed conversion write.

## K2 — P1: protect pending source from encoding reinterpretation

PR anchor: `Sources/Model/NoteObject.m:1345-1351` (introduction of the persistent pending state). Related existing callers: `Sources/ImportExport/EncodingsManager.m:287-318` and `Sources/Model/NoteObject.m:1496-1519`.

After the same canceled conversion, opening Text Encoding and choosing another legacy encoding can replace the pending source with the older file body. `shouldUpdateNoteFromDisk` compares the last observed file date with the current file date. These remain equal when conversion was canceled, so it returns YES without its overwrite warning. `setFileEncodingAndReinterpret:` then reads the stale file and replaces the local body; the next archive flush makes that loss durable.

The probe initializes only the encoding sheet's existing note/file-reference state, calls its production `shouldUpdateNoteFromDisk` predicate, and then executes the operation used by `okAction:`. No overwrite-warning response is injected.

Output: `permits=1 pending=0 liveLocal=0 archivedLocal=0 source=seed cafÈ`. The local emoji edit disappears from both the live model and the unpacked on-disk archive. Reject reinterpretation while pending, or require an explicit decision that preserves the pending source before rereading disk. Gate the model API as well as the sheet so other callers cannot discard these edits.

## Scope

These two bounded histories establish data loss in the new canceled-conversion state. They do not exercise live sync, system crashes, or filesystem failure injection. Source-only metadata edits and shared IME behavior were inspected but are not claimed as additional findings.
