# Round 2: consistency and event ordering

Reviewed HEAD: `5eda58bd50bdda6b31ea705ad1ce6b256ffd671a` (PR #24, base `8dde5e8`). This is a Kyle Kingsbury-inspired review perspective, not a review by Kyle Kingsbury.

No new actionable finding in the tested orderings.

The native probe runs the complete production `NVSourceAnalysis.m`, production URL extraction, and five methods extracted unchanged from `NVNoteEditingSession.m`: character invalidation, syntax invalidation, layout detachment, snapshot capture, and result publication. It uses native `NSTextStorage` and `NSLayoutManager` objects. A one-shot method hook acts immediately before the actual main-queue completion enters production code. The hook chooses the ordering of a main-thread event and a completed result; it does not insert callbacks inside accepted publication.

Executed `python3 Tests/TypingReview/round2/kingsbury/run.py`: **24 checks passed** with AddressSanitizer and UndefinedBehaviorSanitizer. The checks cover:

- Removing the last layout cancels a completed result and leaves link actions stale until reattachment requests current work.
- Removing one of two layouts preserves valid work for the remaining peer.
- Two native character edits that restore identical source still advance the generation and cancel the old ticket. The latest generation receives a new snapshot.
- Two syntax changes that restore the original syntax cancel the old ticket even though character generation does not change.
- Closing analysis before completion delivery suppresses publication.

A negative control removes only the invalidation call in the extracted last-layout detach branch. It fails with `last detached layout cancels queued publication`, confirming the test observes the cancellation boundary.

Runtime evidence and compilation commands are in `results.json` and `output.txt`. Generated copies, native binary, compiler output, sanitizer runs, and the negative-control output are under `build/TypingReview/round2/kingsbury/`.

Limits: This is a deterministic headless boundary test, not a desktop integration test. The note fixture provides syntax; source highlighter is nil. The probe does not cover window-controller ownership, external-file conflict handling, Undo registration, IME composition, or callbacks during accepted attribute publication. It does not establish an upper bound for indivisible worker analysis. No production files were changed.
