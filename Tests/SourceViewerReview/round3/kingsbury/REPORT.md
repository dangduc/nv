# Round 3: durability and concurrent histories

Perspective: Kyle Kingsbury-inspired engineering review. This is not a statement from Kyle Kingsbury.

Reviewed PR #4 baseline: `9720676ccd0e619dba99f6a47d257216c1e383eb`.
The copied Development app contains that baseline. No production files changed during this review.

## Result

No new actionable finding from these bounded histories.

```sh
python3 Tests/SourceViewerReview/round3/kingsbury/run.py
```

The probe passed **112 checks**, with **32 injected WAL synchronization failures**, and exited 0.
`results.txt` retains its check output. The complete local log is `build/round3-kingsbury.log`.

## New executable evidence

The runner compiles `support.h` and `probe-body.m` into an isolated copied app.
It takes `build/pr-review/gui.lock` and uses disposable notes and preferences.
The probe returns `NO` from `WALStorageController.synchronize` during selected histories.
File writes, journal record writes, source conversion, note removal, reconciliation, and archive reopening use production code.
When failure injection stops, synchronization calls the original method.

Each initial conflict history starts with a saved CP-1252 source and an unrepresentable local edit.
An external writer changes the original file before conversion. Failed synchronization prevents replacing that original file.

| History | Observed result |
| --- | --- |
| Edit the conflict note's model before retry | Retry creates a separate copy. The independent edit survives reconciliation and the final file write. |
| Edit the conflict file before directory notification | Retry leaves the edited file intact and creates a separate copy of the original external version. Later reconciliation loads the edited characters. |
| Delete the conflict file, retaining its note | Retry recreates the file under the existing conflict UUID. No extra note is required. |
| Remove the conflict note through the library | Retry creates a new conflict note. It does not reuse the removed note. |
| Two origin UUIDs have identical external bytes | Each origin gets a separate copy. Neither copy matches the other origin. |
| Reopen and retry three times while synchronization fails | Production library initialization preserves both pending origins and their conflict UUIDs. The note count stays constant. |
| Restore successful synchronization after those reopen cycles | Both source conversions complete. The final archive keeps the same note count. |

## Rejected concern

The first probe required an externally edited conflict file to update its model during the first directory scan.
That assertion failed because the conflict note remained in the pending write queue.
The file retained the exact external bytes through the queue drain; the next reconciliation loaded them into the model.

The final probe checks those two boundaries separately. It does not treat deferred model refresh as byte loss.
Automatic file notifications are disabled for deterministic ordering, so the probe invokes both scans explicitly.

## Limits

These histories model an operation reporting synchronization failure. They do not simulate power loss, torn sectors, or kernel failure.
Archive recovery uses successful archive writes and production reopening in copied directories. It is not a process-crash test.
No live sync service or external editor application runs. External changes are completed file writes from the probe.
The tests do not establish protection from a writer racing between the last disk check and source replacement.
Conversion-sheet identity tests from round 2 were reviewed but were not rerun as new evidence here.
