# Round 2: snapshot failure, retry, and close durability

This review uses a Kyle Kingsbury-inspired focus on failure histories and recovery boundaries.
It does not represent his participation or endorsement.

No actionable introduced defect was found in this scope.
The tested failure paths retain dirty state and the WAL until a successful database checkpoint.
The same histories pass on the pre-removal app.

Reviewed production commit: `f38a8cb3f1e5f74c57cfe5e8d5791f364201f1cb`.
Review checkout: `b418d8466d2936de0fb62c8556ce3e0de4b9f106`.
Comparison base: `9693356ae667e8a8143f64fc652f73b19ec2421d`.
The checkout contains a regression-fixture correction after the production commit. Application code is unchanged.

## Original executable evidence

[checks.inc](checks.inc) and [prefix.h](prefix.h) are original code for this round.
They extend the copied-app runner with a controlled store failure, rather than repeating round 1's successful WAL histories.
The fault returns `dskFulErr` (`-34`) only for the selected temporary library's serialized `Notes & Settings` store.
It fires after serialization and before the atomic-store method writes a temporary file or replaces the checkpoint.
It does not fill a disk, alter permissions, or fail the WAL writer.

The histories use disposable notes and a unique app identity, preference domain, and cache journal.
They do not access personal notes, keychain items, credentials, or remote services.

| History | Assertions at the failure boundary and later |
| --- | --- |
| A: edit body/title/tags and local syntax; delete one checkpointed note; fail `flushAllNoteChanges` and `flushEverything` | Both dirty flags remain set. The original checkpoint is byte-for-byte unchanged. The original WAL remains open and can synchronize. No journal close occurs. |
| A retry: permit the serialized store and call `flushEverything` again | The snapshot stores once. Both dirty flags clear. The WAL closes and restarts only after that successful store. Local source, deletion, and syntax remain correct. |
| B: edit again, delete another checkpointed note, and create a new note; fail `closeAllResources` | The library remains dirty. The last successful checkpoint is unchanged. The sole WAL remains open, nonempty, and synchronized, with no additional journal close. |
| Restart after B's abrupt process exit | Actual startup recovery finds exactly three survivors from five known identities. Exact source, title, tags, checkpointed syntax, and newest sequence numbers match the independent ledger. Neither deleted note returns. |
| Clean reopen after recovery | The same three survivors and all checked fields remain correct. Successful resource close removes the obsolete WAL. |

The first process uses `_exit(0)` immediately after the failed close and WAL synchronization.
It bypasses normal application termination, which could otherwise save the database and hide the recovery requirement.
Expected source, title, tags, syntax, and existence come from literal operation expectations.
UUIDs and final journal sequence numbers are recorded separately after those source expectations pass.

## Results and commands

Run from the repository root on macOS 26.5.2 (25F84), Xcode 26.6 (17F113), using the x86_64 app:

```sh
python3 Tests/ViewControlsReview/run-probe.py --probe Tests/SimplenoteRemovalReview/round2/kingsbury/checks.inc --prefix Tests/SimplenoteRemovalReview/round2/kingsbury/prefix.h --app build/SimplenoteRemovalReview/round1.app --launches 3 > Tests/SimplenoteRemovalReview/round2/kingsbury/current.log 2>&1
python3 Tests/ViewControlsReview/run-probe.py --probe Tests/SimplenoteRemovalReview/round2/kingsbury/checks.inc --prefix Tests/SimplenoteRemovalReview/round2/kingsbury/prefix.h --app build/SyntaxFlickerReview/fix.app --launches 3 > Tests/SimplenoteRemovalReview/round2/kingsbury/baseline.log 2>&1
NV_KINGSBURY_DROP_FAILED_WAL=1 python3 Tests/ViewControlsReview/run-probe.py --probe Tests/SimplenoteRemovalReview/round2/kingsbury/checks.inc --prefix Tests/SimplenoteRemovalReview/round2/kingsbury/prefix.h --app build/SimplenoteRemovalReview/round1.app --launches 3 > Tests/SimplenoteRemovalReview/round2/kingsbury/drop-failed-wal.log 2>&1
```

[Current output](current.log): exit **0**.
[Baseline output](baseline.log): exit **0**.
Each passes **71 assertions: 29 before the crash cut, 21 after recovery, and 21 after clean reopen**.
These are two bounded failure histories with three rejected store calls and one successful explicit retry.

```text
KINGSBURY ROUND2 phase1: 29 assertions passed; 2 failure histories, 3 rejected stores, 1 successful retry; crash cut
KINGSBURY ROUND2 phase2: 21 assertions passed
KINGSBURY ROUND2 phase3: 21 assertions passed
```

[Guard-removal control output](drop-failed-wal.log): exit **1**, as expected.
The control calls `closeJournal` after failed `closeAllResources`, simulating removal of its success guard.
It is confined to the copied app process and does not alter production files.

```text
PASS: closeAllResources attempts the failed snapshot store exactly once
PASS: failed resource close leaves the pending local snapshot dirty
FAIL: failed resource close preserves the sole WAL containing local edits, creation, and deletion
```

Executable SHA-256:

- Current `round1.app/Contents/MacOS/nvALT`: `d61aea6619f6c4322efac164d7409ac131aa0ce2a8760d874850c34443331ede`.
- Baseline `fix.app/Contents/MacOS/nvALT`: `ee8e9ca27c99d55ff867afabd49e75c12f5548f49ac93dc733f514f477cac365`.

The baseline app was built at `65e1608`; both commands below produce no application differences:

```sh
git diff --stat 65e1608 9693356 -- Sources Resources Config ThirdParty Notation.xcodeproj
git diff --stat f38a8cb b418d84 -- Sources Resources Config ThirdParty Notation.xcodeproj
```

## Analysis and limits

At `Sources/Storage/NotationController.m:560–573`, both serializer failure and store failure return before clearing dirty state.
At lines 532–539, `flushEverything` gates journal rotation on successful flush.
At lines 742–749, `closeAllResources` retains the same success gate after removal of `stopSyncServices`.
The snapshot's removed remote deletion set is not required to recover the local tombstone tested after failed close.

This fault model represents a whole snapshot-store rejection before replacement, with successful WAL writes and synchronization.
It does not simulate partial filesystem writes, rename/exchange failure, power loss, WAL failure, or failure during startup's own recovery checkpoint.
The explicit retry is a test action; this result does not establish an automatic retry policy.
Syntax is changed before the successful retry checkpoint. No claim is made that uncheckpointed syntax preferences are recoverable from note journal records.
The histories use database storage with library encryption disabled. The WAL retains its existing encryption behavior.
