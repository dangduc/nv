# Org source review, round 2: publication limits and recovery

This review uses a Kyle Kingsbury-inspired perspective on observable state and recovery.
It does not represent Kyle Kingsbury.

No actionable defect emerged from these paths.
The new native probe passed **42 checks** against commit `4dab02a9020ff8f76cceeffc75a001927255a17e`.
The production inputs remained unchanged during the build and run.

## Evidence

Run this command from the repository root:

```sh
python3 Tests/OrgSourceReview/round2/kingsbury/run.py
```

The runner compiles the production highlighter, parser adapter, and every bundled grammar wrapper.
Its parser subclass counts completed requests and captures without changing the returned result.
Its highlighter subclass exposes the analysis flag without changing scheduling, publication, or storage notifications.
The run uses the real main run loop, worker queue, scanner codec, query, and Org supplemental pass.

The first sequence crosses the display limit through layout attachment, without source edits.
A 13,190-unit Org source produces 2,100 captures.
One layout fits the 4,096-operation budget, but two layouts exceed it.
The second attachment clears the whole revision in both layouts and preserves independent search backgrounds.
The remaining layout recovers its current captures immediately after the peer detaches.
Two attachment cycles preserve source and need no extra parser requests.

The second sequence adds a peer after an edit and before the scheduled analysis.
The original layout keeps provisional colors, while the new peer receives no stale absolute ranges.
Both layouts then converge to the current DONE result.
They agree on the corrected distinction between hashtag prose and actual comments.

The same sequence then replaces the source with empty text and restores it.
Both layouts leave plain display after the next successful analysis.
Next, a source with 524,289 UTF-16 units exceeds the analysis length limit by one unit.
The highlighter retains the complete source and clears surviving provisional syntax attributes in both layouts.
After the source shrinks, both layouts recover Org colors without a note reopen.
Every transition keeps syntax attributes out of persistent text storage.

The [output](output.txt) records all checks.
The [metadata](metadata.json) records the input hashes and toolchain.
The host runs macOS 26.5.2 and Xcode 26.6, with Intel code under Rosetta and a macOS 10.13 deployment target.

## Code assessment

`applyCaptures` invalidates the old revision before it evaluates the aggregate display budget.
It retains the capture array after display fallback.
That separation permits immediate recovery after a layout detaches.
The guard evaluates the full capture count across every attached layout, so publication does not stop halfway through a revision.

`storageChanged:` makes semantic captures obsolete before the scheduled analysis.
`layoutsChanged` preserves provisional colors in attached peers while a replacement result remains pending.
The source-length fallback retires parser state and capture tokens.
The next bounded source can create fresh parser state and recover display.

## Limits

These are two deterministic state sequences, not an exhaustive scheduler search.
They supplement round 1's controlled obsolete-result and closure schedules.
They do not independently exercise browser controllers, link attributes, Undo, IME composition, disk persistence, or actual macOS 10.13 execution.
The display-limit fixture does not measure painting latency or memory under heavy load.
No production files changed for this review.
