# Round 3: correctness, Unicode, and selections

AI review perspective inspired by Linus Torvalds; this is not a review by that person.

PR: <https://github.com/dangduc/nv/pull/1>. Reviewed head: `3502c7c49660cb4750a9de7f02fedd7e6fd314e8`. Compared with base `4c6cf45` and the preceding reviewed head `4008592`.

## P2: preserve selections inside unchanged text between separate edits

Location: `NVNoteEditingSession.m:50-53`.

`NVChangedRange` trims the common prefix and suffix, then `applyContents:` applies one contiguous replacement. When an external update changes text on both sides of a selection, that replacement includes the unchanged selected text. Cocoa therefore treats the selection as deleted and collapses it to the replacement end. The round-two fix handles one contiguous edit but leaves this case unresolved.

Executed reproduction:

1. A and B display `AAcoreZZ`; B selects `core`, range `{2, 4}`.
2. An external model update changes the note to `BBcoreYY`.
3. B moves to `{8, 0}`, although `core` is unchanged.

Expected: B retains `{2, 4}`. A native `NSTextView` reference that applies the two actual replacements retains that range. The note body itself remains correct. The next typing action in B can append instead of replacing the selected middle text.

Apply separate changed spans, or preserve and transform selections across unchanged interior spans when restoring a snapshot. Include this two-sided update in the selection regression tests.

## Executed evidence

```sh
python3 Tests/ReviewEvidence/round3/torvalds/run-probes.py
```

Eleven checks passed, including an assertion demonstrating the remaining defect. The runner used a copied app, temporary notes, a random preferences domain, the shared GUI lock, and a 90-second app timeout. Rosetta execution used process-sandbox escalation. `measurements.txt` records the expected and actual ranges; the full local log is `build/pr-review/round3-torvalds.log`.

## Checks without findings

The round-two suffix undo/redo reproduction now preserves the peer selection. Prefix insertion with a surrogate-pair emoji shifts the selection by UTF-16 length. Changing an emoji whose surrogate pair shares its first code unit preserves the complete text and peer range. Attribute-only updates preserve two selected ranges and apply both independent font and underline runs. These checks produced no additional finding. Live sync and external editor applications were not exercised; the external-update probe uses the note model entry point.
