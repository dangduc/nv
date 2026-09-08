# Round 3: legacy migration followed by local crash recovery

This review uses a Kyle Kingsbury-inspired focus on failure histories and recovery boundaries.
It does not represent his participation or endorsement.

No actionable introduced defect was found in this scope.
The corrected old library can recover later local edits from its journal before its first successful migration checkpoint.
The recovered snapshot removes remote fields and retains the checked local state through a clean reopen.

Reviewed production commit: `f38a8cb3f1e5f74c57cfe5e8d5791f364201f1cb`.
Review checkout: `f9cc501`.
Application code is unchanged since the production commit.
The permanent fixture correction from `b418d84` is included in this review.

## Original executable evidence

[checks.inc](checks.inc) and [prefix.h](prefix.h) implement a new three-process history.
The probe composes the real legacy migration with local WAL recovery.
Earlier rounds tested archive reads and recovery from newly created libraries separately.

The input is the [corrected permanent fixture](../../../Regression/source-storage/fixtures/legacy-simplenote.notation).
The pre-removal app wrote this artifact with its recognized `SN` service identifier.
It contains an enabled synthetic account, one local note with pending upload metadata, and one pending remote deletion.
Its [provenance](../../../Regression/source-storage/fixtures/README.md) describes the producer's positive controls.
The current review checks the artifact hash before every process opens it.
It never launches the old app against the enabled account.

| Input | SHA-256 |
| --- | --- |
| Corrected 4,233-byte old archive | `07bc028440a8dfba96f53023f3035141a94c5b1ecd8b6cd23d99eaeb9bf52f4d` |
| Current frozen executable | `d61aea6619f6c4322efac164d7409ac131aa0ce2a8760d874850c34443331ede` |

The copied-app runner supplies a unique bundle ID, disposable notes and preferences, and a separate cache journal.
No personal notes, credentials, keychain data, or remote services are used.

## History and oracle

1. Before process one initializes its actual library controller, the prefix installs the unmodified old archive as `Notes & Settings`.
2. The live library contains the old fixed UUID, exact unsent source and UTF-8 bytes, title, tags, dates, sequence 1, and local Markdown syntax.
3. A body/title/tag edit and explicit journal drain produce sequence 2. Deletion produces sequence 3. Undo restores the same UUID at sequence 4.
4. Creation adds a second fixed UUID at sequence 1. Another fixed UUID is created and deleted, ending with a sequence 2 tombstone.
5. A normal `flushAllNoteChanges` serializes the changed library and drains its WAL. The prefix rejects only snapshot replacement with `dskFulErr`.
6. The real WAL exists and its explicit `synchronize` succeeds. The database still equals the entire old 4,233-byte artifact. `_exit(0)` bypasses termination and checkpoint flushing.
7. Process two checks the old checkpoint bytes before startup. The actual startup recovery path reads the WAL and checkpoints the recovered state normally.
8. Process three opens the rewritten library after normal termination and checks the same state again.

The snapshot substitution preserves a precise crash boundary: the old archive plus durable new journal records.
It is a whole-store rejection before replacement, not a claim about physical disk-full behavior.
No note serialization, WAL record, recovery method, sequence comparator, or decoder is replaced.

Each process constructs the same literal ledger in code.
UUIDs, bodies, titles, tags, syntax, creation dates, and final sequence numbers do not come from recovered objects or a newly encoded fixture.
The expected survivors are the edited legacy note at sequence 4 and the new note at sequence 1.
The source oracle checks characters and exact exported UTF-8 bytes, including CRLF, tabs, accents, Japanese text, and supplementary Unicode characters.
Both the remote tombstone identity and the newly deleted local identity must remain absent. The total live count must be two.

After recovery, the outer keyed archive must omit `syncServiceAccounts` and `deletedNoteSet`.
The decompressed inner note archive must omit `syncServicesMD`.
An independent snapshot reread also verifies that two local notes decode successfully.

## Commands and results

Run from the repository root on macOS 26.5.2 (25F84), Xcode 26.6 (17F113), with the x86_64 app:

```sh
NV_MIGRATION_FIXTURE="$PWD/Tests/Regression/source-storage/fixtures/legacy-simplenote.notation" python3 Tests/ViewControlsReview/run-probe.py --app build/SimplenoteRemovalReview/round1.app --prefix Tests/SimplenoteRemovalReview/round3/kingsbury/prefix.h --probe Tests/SimplenoteRemovalReview/round3/kingsbury/checks.inc --launches 3 > Tests/SimplenoteRemovalReview/round3/kingsbury/current.log 2>&1
NV_MIGRATION_DROP_WAL=1 NV_MIGRATION_FIXTURE="$PWD/Tests/Regression/source-storage/fixtures/legacy-simplenote.notation" python3 Tests/ViewControlsReview/run-probe.py --app build/SimplenoteRemovalReview/round1.app --prefix Tests/SimplenoteRemovalReview/round3/kingsbury/prefix.h --probe Tests/SimplenoteRemovalReview/round3/kingsbury/checks.inc --launches 3 > Tests/SimplenoteRemovalReview/round3/kingsbury/dropped-wal.log 2>&1
```

[Positive output](current.log): exit **0**, **73 assertions** across three processes.
Hash and pre-open checkpoint gates also pass.
The recorded process-one fault rejects one 3,265-byte serialized snapshot.
Its compressed size can vary because new note modification times use the current clock.

```text
KINGSBURY ROUND3 CRASH CUT: 31 assertions, rejected stores=1
KINGSBURY ROUND3 phase2: 21 assertions passed
KINGSBURY ROUND3 phase3: 21 assertions passed
```

[Negative control](dropped-wal.log): exit **1**, as expected.
After all pre-crash positive assertions pass, the control deliberately deletes only the disposable journal through `closeJournal`.
Process two still starts from the exact old archive, but its recovered source fails the literal oracle:

```text
CONTROL: deliberately remove the durable WAL before abrupt exit
FAIL: exact source and exported bytes match: Migrated local title
```

This demonstrates that the positive result depends on the actual journal recovery path.
The probe cannot pass by reading only the original checkpoint.

## Limits

This is one bounded migration history with successful WAL writes and synchronization.
It does not simulate torn records, failed WAL synchronization, power loss, filesystem exchange failure, or failure during startup's recovery checkpoint.
Database encryption is disabled in this historical fixture; the journal uses its existing encryption implementation.
Local syntax already exists in the old snapshot. The new note keeps default plain syntax.
The probe does not claim durability for a new syntax preference that was never checkpointed.
Creation dates are fixed and checked; wall-clock modification dates after editing are not part of the exact ledger.
The negative control removes the whole journal and does not model unsynchronized writes.
