# Round 2: Dan Luu-inspired review

This review uses a Dan Luu-inspired focus on observed UI transitions. It does not represent his authorship.

Reviewed application commit: `504f30353275663d5174656b03805625275e603a`. The evidence-only HEAD at review start was `efa6e0a`.
The review cross-read all five round 1 reports and examined their probe code.

## Findings

No actionable findings.

`newNote:` snapshots Search before it clears the field (`Sources/Browser/AppController_BrowserUI.m:319`).
The command establishes the next note and editor focus before another command arrives.
Native deletion supplies an empty title and correctly uses the localized fallback.
Successive commands preserve edits to the preceding note.

## Executed evidence

```sh
python3 Tests/ViewControlsReview/run-probe.py \
  --probe Tests/FocusedSearchNewNoteReview/round2/luu/checks.inc \
  > Tests/FocusedSearchNewNoteReview/round2/luu/output.txt 2>&1
```

Result: **45 checks passed**, exit 0. The run used the copied app and a disposable library.
The shared runner serialized desktop access with `build/pr-review/gui.lock`.

The probe ran these paths with the title header hidden and visible:

- Select all text in a populated Search field, then delete through the native field editor.
- Press Command-N after the deletion. The empty focused field supplies the localized default title.
- Press Command-N twice more without a fixture `Pump` between commands. Each command selects a distinct new note with the expected focus.
- Create from a populated fuzzy Search field, then edit the new note before the next Command-N.
- With the title header hidden, enter source text. The next command preserves that text in the preceding note.
- With the title header visible, enter a title. The next command commits that title in the preceding note.
- Compare total note count after delayed callbacks. Ten commands create ten distinct notes, with empty source in each final new note.

These paths extend round 1 coverage of Unicode, title snapshots, duplicate titles, and delayed search callbacks.

## Environment and limits

- macOS 26.5.2 (25F84), Xcode 26.6 (17F113), Intel app through Rosetta.
- Executable SHA-256: `ffd2506757bfb23cfc26450ce1a736a578babd22af606a313427a6db7e399c43`.
- The probe dispatches the real menu key equivalent. It does not synthesize hardware key-repeat events.
- Native insertion and deletion send their normal control notifications. New Note and metadata code execute unchanged inside the existing isolation harness.
- The probe checks immediate note state and delayed callbacks. It does not repeat persistence, Unicode, or broad desktop suite coverage.
- No production code changed during this review.
