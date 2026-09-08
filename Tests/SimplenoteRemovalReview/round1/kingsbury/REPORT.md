# Round 1: local consistency and recovery

This review uses a Kyle Kingsbury-inspired focus on operation histories and recovery boundaries. It does not represent his participation or endorsement.

No actionable introduced defect was found in this scope.

The review compares `f38a8cb3f1e5f74c57cfe5e8d5791f364201f1cb` with `9693356ae667e8a8143f64fc652f73b19ec2421d`.
It covers local deletion ordering, deletion Undo and Redo, and recovery after removal of the remote deletion set.

## Evidence

[checks.inc](checks.inc) is original native code loaded into an isolated app by the existing review harness.
[prefix.h](prefix.h) contains an optional ordering mutation used only for the negative control.
The harness copies the app, uses temporary notes, and selects a unique preferences and cache domain.
No personal notes, account settings, credentials, or network service are used.

The first process saves nine notes as a database checkpoint. It then runs these eleven histories:

| History | Expected state after recovery |
| --- | --- |
| Edit queued body, then delete | Absent |
| Edit source, title and tags, then delete and Undo | Present with all edits |
| Delete, Undo, Redo | Absent |
| Edit source after checkpoint | Present with edited source |
| Batch delete and Undo, first note | Present |
| Batch delete and Undo, second note | Present |
| Twenty delete and Undo cycles | Present with the newest sequence |
| Delete and Undo, then append an older tombstone | Present with the newer note record |
| Untouched control | Unchanged |
| Create and delete after checkpoint | Absent |
| Create, delete and Undo after checkpoint | Present |

The test checks live source, title, tags, and syntax against literal expected values before saving an independent expected-state ledger.
It confirms that the database bytes still match the original checkpoint, then synchronizes the WAL and calls `_exit(0)`.
That bypasses the normal termination flush.
The second process uses the actual application startup recovery path.
The third process reopens the recovered database after a normal save and termination.
Both must recover exactly eight notes, with the expected UUIDs, source characters, metadata, and sequence numbers.
Syntax is set before the checkpoint because local syntax settings are stored in the database, not note journal records.

The native history passed against both app versions:

- [Current app output](current.log): exit 0; 25 assertions before the crash cut, 48 after recovery, and 48 after the clean reopen. Total: 121 assertions.
- [Baseline app output](baseline.log): exit 0; the same 121 assertions passed.
- [Broken ordering output](broken-order.log): exit 1 during the second launch. The test reports `FAIL: restart history dirty-delete has expected existence=0`.

The mutation makes both note classes refuse every newer journal sequence. The failed check detects a resurrected checkpointed note.
The mutation does not edit production files or the saved app.

## Commands

Run from the repository root on macOS 26.5.2 (25F84), Xcode 26.6 (17F113):

```sh
python3 Tests/ViewControlsReview/run-probe.py --probe Tests/SimplenoteRemovalReview/round1/kingsbury/checks.inc --prefix Tests/SimplenoteRemovalReview/round1/kingsbury/prefix.h --app build/SimplenoteRemovalReview/round1.app --launches 3 > Tests/SimplenoteRemovalReview/round1/kingsbury/current.log 2>&1
python3 Tests/ViewControlsReview/run-probe.py --probe Tests/SimplenoteRemovalReview/round1/kingsbury/checks.inc --prefix Tests/SimplenoteRemovalReview/round1/kingsbury/prefix.h --app build/SyntaxFlickerReview/fix.app --launches 3 > Tests/SimplenoteRemovalReview/round1/kingsbury/baseline.log 2>&1
NV_KINGSBURY_BROKEN_ORDER=1 python3 Tests/ViewControlsReview/run-probe.py --probe Tests/SimplenoteRemovalReview/round1/kingsbury/checks.inc --prefix Tests/SimplenoteRemovalReview/round1/kingsbury/prefix.h --app build/SimplenoteRemovalReview/round1.app --launches 3 > Tests/SimplenoteRemovalReview/round1/kingsbury/broken-order.log 2>&1
```

Executable SHA-256:

- Current `round1.app/Contents/MacOS/nvALT`: `d61aea6619f6c4322efac164d7409ac131aa0ce2a8760d874850c34443331ede`.
- Saved baseline `fix.app/Contents/MacOS/nvALT`: `ee8e9ca27c99d55ff867afabd49e75c12f5548f49ac93dc733f514f477cac365`.

The saved baseline was built for `65e1608`. This check produces no output:

```sh
git diff --stat 65e1608 9693356 -- Sources Resources Config ThirdParty Notation.xcodeproj
```

An initial probe compile failed because its prefix used a category before importing `NoteObject.h`.
The missing import was corrected before all three recorded runs. No production change followed from that harness error.

## Analysis

[removeNote:](../../../../Sources/Storage/NotationController.m#L1083) still drains queued writes before it records the deletion.
[writeRemovalForNote:](../../../../Sources/Storage/WALController.m#L186) still advances the original note sequence before it creates the local tombstone.
The [tombstone constructor](../../../../Sources/Model/DeletedNoteObject.m#L28) preserves the UUID and sequence after removal of remote metadata and the original-note reference.
The library Undo manager still retains the note through [its registered Undo invocation](../../../../Sources/Storage/NotationController.m#L1123).

The [WAL coalescer](../../../../Sources/Storage/WALController.m#L529) retains the record with the greatest sequence for each UUID.
The [recovery merge](../../../../Sources/Storage/NotationController.m#L465) still removes checkpointed notes when their tombstone is newer.
Ignoring a tombstone for an absent checkpointed note does not resurrect its earlier journal version: coalescing has already removed that version.
The post-checkpoint creation/deletion history exercises that case through real startup.

## Limits

These are bounded local histories with explicit successful WAL synchronization. They do not establish behavior after power loss, disk-full errors, partial writes, corrupted records, or sequence rollover.
The history uses database storage and the standard unencrypted-library configuration. WAL records still use their existing encryption mechanism.
The late older tombstone is a deliberate journal-order fixture, not a claim that this physical order occurs during ordinary editing.
The baseline and current results support preservation of the tested behavior; they do not prove all recovery behavior correct.
