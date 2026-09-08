# Round 1: contrarian integration review

This review challenges two assumptions: that hidden controls preserve normal workflows, and that test order cannot conceal integration defects.
No actionable PR regression was established in these histories.

## Evidence

`checks.inc` runs against the real application at frozen head `162c872`.
The shared runner uses a copied app, a disposable library, a unique defaults domain, and the desktop-test lock.
The probe uses a 480-point content width. It does not widen the window before checking the new controls.

Three histories run Search before View commands:

1. Use the stock toolbar and open Search.
2. Remove the Search item through the native toolbar API, then restore it with the Search command.
3. Hide the toolbar, then restore it with the Search command.

For each history, the probe hides the title, tags, body controls, and notes list while Search has its native field editor.
It then checks these operations:

- Type a query into the field editor and filter notes.
- Press Tab to reach the editable source.
- Dispatch Show Preview and Show Source through the application menu targets.
- Reveal the title with Rename and the tags with Tags.
- Toggle Word Count twice and verify its visibility, preference, and menu check.
- Create a note while all note rows and the list are hidden.
- Enter and commit source text in the new note.
- Preserve the original notes' exact source characters.

All six shipped localizations completed these histories with 184 checks each: `en`, `de`, `fr`, `it`, `pt-PT`, and `zh`.
Each log records the bundle's selected localization.
All localized Word Count menu items had their old value binding removed at runtime.
The native action changed the stored preference to its inverse, and the menu check matched the resulting visibility.

The first `zh` launch failed to obtain Search focus before any View command. No production code changed before the successful repeat.
`output-zh-initial-fixture-failure.txt` preserves that result. The successful repeat includes Search responder diagnostics in `output-zh.txt`.
This run does not establish the cause of that transient failure. It does not support attributing a new regression to the View controls.

## Reproduction

From the repository root:

```sh
python3 Tests/ViewControlsReview/round1/contrarian/run-localizations.py
```

Pass locale names to run a subset. Use `--app` to select another Development build:

```sh
python3 Tests/ViewControlsReview/round1/contrarian/run-localizations.py \
  --app build/DerivedData/Build/Products/Development/nvALT.app en zh
```

## Limits

The tests exercise AppKit field editors, menu validation, action routing, and toolbar customization APIs.
They do not synthesize pointer clicks or evaluate translated wording.
The test proves the checked workflows can run after Search customization. It does not prove every workflow order is equivalent.
No base-build comparison was needed for an actionable finding because no repeatable PR defect was established.
