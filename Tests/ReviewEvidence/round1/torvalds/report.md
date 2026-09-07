# Round 1: correctness and ownership review

AI review perspective inspired by Linus Torvalds; this is not a review by that person.

Reviewed snapshot: `30791c5`, compared with `4c6cf45`. PR: <https://github.com/dangduc/nv/pull/1>.

## P2: reload cached hidden notes after changing the body font

Location: `AppController.m:1009-1011`.

`restyleAllNotes` updates every note model, but this loop reloads only notes currently displayed in a browser. Previously displayed notes keep their old `NVNoteEditingSession` storage. Reopening such a note attaches the stale storage; the next edit writes its old font back into the model.

Reproduction in the copied app:

1. Open Alpha, then switch to Beta.
2. Change the body font from 12 pt to 21 pt through the preference callback.
3. Reopen Alpha and type one character.

Observed: Alpha's model initially changes to 21 pt, its cached storage and reopened editor remain 12 pt, and typing changes the model back to 12 pt. Expected: the font change reaches all cached sessions and remains applied after reopening and editing.

Refresh all affected editing sessions when model styling changes, while retaining the existing marked-text handling. Add a regression check for a cached note that is not visible in any window.

## Executed evidence

```sh
python3 Tests/ReviewEvidence/round1/torvalds/run-probes.py
```

Run with process-sandbox escalation so Rosetta can launch. The runner serializes GUI access with `build/pr-review/gui.lock`, uses a copied app and temporary notes/defaults, and limits the app subprocess to 90 seconds. `probes.m` contains the reproduction; `measurements.txt` contains the measured font values. Seven checks passed, including checks that demonstrate the defect.

## Other coverage and limits

Inspected manual ownership, shared layout-manager attachment, undo routing, and application/library shutdown. No additional actionable defect established in those paths. Browser deallocation is covered by the independent ownership review.

The probe also confirms that a deleted note's editing session remains cached after undo histories clear. This is a retention observation, not a second finding: this round did not establish an intended cache bound or quantify sustained memory growth. Live sync and external editor processes were not exercised.
