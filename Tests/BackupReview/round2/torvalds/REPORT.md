# Round 2: resource lifetime and deletion contracts

Review lens: Linus Torvalds-inspired attention to low-level correctness, resource lifetime, and simple contracts.
This is an agent review, not a review by Linus Torvalds.

Reviewed baseline: `a89f8351646f824f51ed6ea80b94f724f37d0303`.
The initial PR baseline is `30c3cf816c80e4ff957223d55f22b36074880ef1`.
The comparison base is `119c45302123c14d02dd0c9b620709bf68e6f086`.
The review includes `AGENTS.md`, `architecture.md`, the store, and its controller call sites.

## Actionable finding

**P2: Bind explicit plaintext deletion to the active library identity.**

Location: `Sources/Storage/NVBackupStore.m:660-665`.
Caller: `Sources/Storage/NVBackupController.m:369`.
This finding applies to the PR feature and predates the round 1 fixes.

The confirmation dialog limits deletion to the current library.
The controller supplies only the destination URL to the store.
The store reads the owner from that destination and uses that owner to select plaintext snapshots.
It never compares that owner with the active library UUID.

If a user copies another library's backup folder into the current library's destination, explicit deletion removes that other library's plaintext backups.
The probe copies library B's complete folder beneath library A's UUID child.
The new maintenance method rejects the owner mismatch with `EINVAL` and preserves both snapshots.
The path-only deletion method succeeds and deletes B's plaintext snapshot.
It preserves B's encrypted snapshot.
This fixture uses ordinary copies and disposable content, with no links or concurrent mutation.

Pass the captured active library UUID into explicit deletion and reject an owner mismatch before snapshot enumeration.
For a selected root, also pass its captured filesystem identity through the same operation-directory boundary that publication and maintenance use.
The existing metadata-aware maintenance method supplies the required pattern.
The deletion method must not infer the authorized library from the destination's current owner.

## Other results

The new maintenance method preserves all snapshots on the tested identity, path, lock, and injected pruning failures.
Missing default ancestors, selected roots, and library children remain absent.
The method creates no missing directories.

The tests create nine equal-date snapshots with one generation number.
Retention preserves the designated current snapshot and three complete snapshots after a final directory-sync failure.
A retry succeeds and clears the previous error.
The tests establish logical retry behavior, not persistence after power loss.

The tested maintenance paths close every descriptor.
The descriptor count remains three after repeated rejection paths, retention, retry, and explicit deletion.
Manual memory management and strict compiler warnings remain enabled.

## Executable evidence

Environment: macOS `26.5.2` (`25F84`), Xcode `26.6` (`17F113`), native `arm64` Foundation.

Commands and results:

```text
$ python3 Tests/BackupReview/round2/torvalds/run.py
OBSERVED: misplaced library B folder under library A's child: maintenance rejects ownership; path-only plaintext deletion deletes B's plaintext snapshot.
PASS: 516 checks; 160 rejected maintenance calls; equal-date protection and sync retry; descriptor count 3 -> 3

$ python3 Tests/BackupStore/run.py
PASS: 372 backup store assertions

$ python3 Tests/BackupReview/round1/torvalds/run.py
PASS: 691 checks; 140 injected publication failures, 20 real lock-contention failures, 20 partial-restore failures; descriptor count 3 -> 3
```

The new driver compiles production `NVBackupStore.m` without source extraction or replacement.
It uses the existing test-only failure hooks and real `flock` contention.
Its filesystem fixtures reside in a temporary directory that Python deletes after the run.
The probe records the ownership defect as an observed baseline behavior.
After a deletion API fix, that assertion needs the corrected contract.
No production files or commits changed during this review.

## Limits

The tests do not run the Intel application or its full Cocoa restore flow.
The host's previously reported startup stall excludes that path from this review.
Descriptor counts do not establish absence of heap leaks.
These tests do not simulate power loss, remote filesystems, or concurrent external file mutation.
The controller call and confirmation dialog were reviewed in source, not exercised through the application UI.
