# Round 3: bounded history state matrix

AI review perspective inspired by Kyle Kingsbury. No participation or endorsement by the named person is implied.

Reviewed source and app: `3502c7c`. Incremental fixes were reviewed from `4008592`; the feature base remains `4c6cf45`.

## Result

No new actionable finding in the tested interleavings. The new evidence independently validates the no-op snapshot fix and the external-update history checkpoint.

The probe runs seven external revision sequences with both a prefix and a suffix composition:

| External sequence | Verified history behavior |
| --- | --- |
| Identical snapshot | Retains earlier local undo actions |
| Changed, then reverted | Retains earlier local undo actions |
| Three identical snapshots | Retains earlier local undo actions |
| Changed snapshot | Preserves a remote checkpoint |
| Changed, reverted, then changed | Preserves the latest remote checkpoint |
| Style changed, then reverted | Retains earlier local undo actions |
| Style changed | Preserves the external style checkpoint |

Each case commits an earlier local edit, starts native marked text, and delivers external snapshots. Another browser invokes Undo, which finalizes the composition. The probe checks a second Undo, two Redo commands, and three further Undo/Redo cycles. It compares the note model with explicit expected strings and checks both browser views and conflict-note counts.

Net no-ops produced no conflict notes and retained earlier undo history. Real revisions survived repeated history operations. External style attributes remained on the original text.

Additional cases confirmed that real same-position insertions retain exactly one external conflict copy through repeated Undo/Redo. Closing the composing browser committed a disjoint merge; the remaining browser could undo and redo its local part.

## Executable evidence

```sh
python3 Tests/ReviewEvidence/round3/kingsbury/run-probes.py
```

Result: exit 0; **210 assertions passed**.

```text
KINGSBURY ROUND 3 PROBES COMPLETED (210 checks)
```

The runner copies the built app and uses temporary notes, a random preferences domain, the shared GUI lock, and a 90-second Cocoa subprocess timeout. Run outside the restrictive process sandbox after the documented Development build.

## Limits

This is a deterministic, bounded matrix, not exhaustive state exploration. External updates enter through the real note model. Live sync, external editor applications, crash recovery, and disk-failure injection were not exercised. The probe checks text, style checkpoints, history, and conflict copies; it does not establish selection behavior for all disjoint character changes.
