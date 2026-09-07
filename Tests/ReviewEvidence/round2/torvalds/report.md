# Round 2: correctness and editor contracts

AI review perspective inspired by Linus Torvalds; this is not a review by that person.

PR: <https://github.com/dangduc/nv/pull/1>. Reviewed head: `4008592b06c6e634d5e3967f9f4c7d78bad50ef0`. Compared the feature against base `4c6cf45` and fixes in `30791c5...4008592`.

## P2: preserve peer editor selections when restoring shared text

Location: `NVNoteEditingSession.m:76`. The same issue occurs in the model reload at line 58.

Replacing the entire shared text storage causes Cocoa to collapse selections in every attached editor to the document end. Undo in one window therefore changes another window's selection even when the edited characters are after that selection. A later keystroke in the peer window appends text instead of replacing its previously selected text.

Executed reproduction:

1. Both windows display `abcdefghij`; B selects `bcd`, range `{1, 3}`.
2. A appends `X`: B correctly retains `{1, 3}`.
3. A invokes Undo: B moves to `{10, 0}`.
4. A invokes Redo: B moves to `{11, 0}`.
5. Reset B to `{1, 3}` and append `Y` through the note model: B moves to `{12, 0}`.

Expected: B retains `{1, 3}` through these suffix changes. Preserve or transform each attached editor's selection when applying a snapshot, or apply the changed range instead of replacing all characters. Include undo, redo, and external-update regression checks.

## Executed evidence

```sh
python3 Tests/ReviewEvidence/round2/torvalds/run-probes.py
```

Nine checks passed, including assertions that demonstrate the selection defect. The runner uses a copied app, temporary notes, a random preferences domain, `build/pr-review/gui.lock`, and a 90-second app timeout. It ran with process-sandbox escalation for Rosetta. `measurements.txt` records the actual ranges; the full local log is `build/pr-review/round2-torvalds.log`.

## Other coverage and limits

Rechecked the hidden cached-note font fix: the cached editor received the new font after the note became hidden. Ordinary appended text preserved the peer selection, and undo/redo restored the expected shared text. Reviewed the incremental session-refresh API and ownership boundaries without another actionable finding. Preview ownership, global column visibility, and no-op external-update conflicts belong to other round-two reviews. Live sync was not exercised.
