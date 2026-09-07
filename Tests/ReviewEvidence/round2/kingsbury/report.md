# Round 2: external-update ordering and history

AI review perspective inspired by Kyle Kingsbury. No participation or endorsement by the named person is implied.

Reviewed commit: `4008592`; incremental review from `30791c5`, with original base `4c6cf45`.

## P2: An unchanged external snapshot creates a conflict and clears undo history

Location: `NVNoteEditingSession.m:117-125`.

During marked text, `reloadFromNote` queues every external snapshot, including one equal to the committed attributed contents. At commit, the session clears existing history. It then treats the unchanged external text's empty range as an insertion at the end. Appending a composition at that position therefore enters the conflict-copy branch.

The new native Cocoa probe starts with `base`, commits `!`, then starts an appended `LOCAL` composition. It delivers an external snapshot exactly equal to `base!`, including attributes. Finishing the composition changes the note count from seven to eight. A conflict note appears despite no external change. Undo removes `LOCAL`, but a second undo cannot remove the earlier `!`.

Expected: Preserve `base!LOCAL` without a conflict copy, and retain both local edits in undo history.

Actual: Local text survives, but an extra note appears and the earlier undo action is lost.

Discard an unchanged deferred snapshot before creating a conflict or establishing a history checkpoint. Preserve real same-position conflicts and real external-update checkpoints.

## Executable evidence

```sh
python3 Tests/ReviewEvidence/round2/kingsbury/run-probes.py
```

Result: exit 0; 40 assertions passed. Assertions labeled `BUG` reproduce the new finding. Run outside the restrictive process sandbox after the documented Development build. The runner uses a copied app, temporary notes, a random preferences domain, the shared GUI lock, and a 90-second subprocess timeout.

Relevant output:

```text
EVIDENCE unchanged-external before=7 after=8 text=base!LOCAL
PASS: BUG no-op external notification creates a spurious conflict copy
PASS: BUG no-op external notification erased the preceding committed edit's undo action
KINGSBURY ROUND 2 PROBES COMPLETED (40 checks)
```

## Coverage with no finding

The new matrix independently confirmed the round 1 P1 fix. Undo preserved remote text, repeated undo respected the external checkpoint, and redo restored the expected merge. Cases included insertion before a remote suffix, remote growth and shrinkage before a local replacement, adjacent replacements, and a Unicode prefix. Two successive external snapshots used the latest snapshot. Both browsers agreed after every history operation. Disjoint merges created no conflict copies.

Live sync and external editor applications were not exercised. External updates entered through the real note model. This run did not test crash recovery.
