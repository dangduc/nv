# Round 2: durability and concurrent histories

Perspective: Kyle Kingsbury-inspired review. This is an engineering lens, not a statement from Kyle Kingsbury.

Reviewed storage baseline: `f037c7b781fa2a3c58d7b00cb440ba3e7239b615` in PR #4.

## Evidence

```sh
python3 Tests/SourceViewerReview/round2/kingsbury/run.py
```

`output.log` records 33 completed checks. The runner takes `build/pr-review/gui.lock`, copies the Development app, and creates disposable notes and preferences.
It compiles new Objective-C evidence into the copied app. Production import, mutation, deletion, conversion, file writes, conflict preservation, reconciliation, journal records, and archive decoding run unchanged.

For the first histories, the probe captures the actual conversion-sheet completion instead of displaying the sheet. It supplies the test window as `NSApplication.mainWindow` so an inactive copied app takes that path. The probe then models another window deleting the note before the user accepts conversion.

For the failure history, the probe returns `NO` at the production WAL synchronization boundary three times. The file and WAL record writes still use production code. Successful synchronization calls the original method. This models a reported synchronization failure, not a power-loss or kernel-fault experiment.

The checks labeled `REPRO` assert the observed bugs. They are evidence, not permanent correctness expectations.

## K3 — P2: reject conversion completions for deleted notes

PR anchor: `Sources/ImportExport/EncodingsManager.m:109`. Presentation has the same missing membership guard at line 99.

The retained conversion request checks only that its library is still active. Deleting its note from another browser leaves that library active and the note retained. Accepting the old sheet calls `upgradeEncodingToUTF8`, which writes directly before the library can reject the subsequent dirty-note scheduling.

Observed history:

1. Import and save a CP-1252 file, append an emoji, and open its conversion offer.
2. Remove the note through `NotationController.removeNote:` while the offer is outstanding.
3. Complete the original production sheet callback with `NSAlertFirstButtonReturn`.
4. Reconcile the directory.

Output: `member=0 recreated=1`. The callback recreates the deleted source file. Directory reconciliation then resurrects its source as a note.

A second history creates and flushes a new note with the same available filename between deletion and acceptance. The stale callback removes that new note's file from its acknowledged path and writes the deleted content into `replace-pending.1.txt`. The new content survives in an unexpected `replace-pending (external changes).txt` copy. The replacement model still has its characters immediately after reconciliation, but its `noteFilePath` is `nil`. This establishes unintended cross-note file mutation, not total loss of every source copy.

Check note membership before both presenting and completing the request. Invalidate outstanding offers when a note is removed; a library identity check alone cannot protect note lifetime.

## K4 — P2: reuse a pending conflict copy after synchronization failure

PR anchor: `Sources/Storage/NotationController.m:831-839`.

`preserveExternalSourceData:encoding:forNote:` adds a fresh note before attempting its durable writes. A `NO` synchronization result keeps that copy in `allNotes` and leaves the original disk baseline unchanged. Every retry therefore creates a fresh copy of exactly the same external bytes.

Observed history:

1. Save an unrepresentable local edit in the pending-conversion state.
2. Complete one distinct external source write.
3. Fail the conflict WAL synchronization three times while retrying conversion.
4. Allow the next retry to synchronize and finish; flush and decode the library archive.

Output: `failedSyncs=3 duplicateCopies=3`. Successful retry leaves four identical external-change notes and files. Archive decoding confirms all four records persist. No new external source version occurred between retries.

Reuse the retained pending copy by original note and external version, and retry its persistence before advancing the baseline. Removing a failed attempt requires care because it may already have a file or a journal record.

## Rejected hypothesis and limits

The failure history did **not** overwrite external source before synchronization reported success. Each failed attempt retained the exact external disk bytes and pending local source. Successful conversion retained every local character. The existing round-1 preservation fix therefore protects these contents in this bounded failure history.

This review does not claim crash recovery after a real failed `fsync`, sustained disk exhaustion, live Simplenote behavior, or all external-write interleavings. It does not test a file-write failure; the injected boundary is WAL synchronization. No production files were changed by this review agent.
