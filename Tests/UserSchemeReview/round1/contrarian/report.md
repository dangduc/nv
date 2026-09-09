# Round 1: contrarian review

No actionable defect found in the localized Settings layout or native color-panel routing.

This review challenges the assumption that tests of the English pane and direct action dispatch cover the new controls.
It uses a contrarian engineering perspective, without attributing the review to another person.

## Evidence

`probe.inc` explicitly loads all six compiled Preferences nibs: English, German, French, Italian, Portuguese, and Chinese.
Each nib uses the real `PrefsWindowController` and its production layout code.
The probe opens Fonts & Colors and checks:

- Both scheme groups exist and do not overlap.
- All six wells fit within their groups and pane.
- All six localized labels fit within their assigned widths and group bounds.
- Every well targets the controller that owns the pane.
- Exclusive `NSColorWell` activation and `NSColorPanel.setColor:` change only the selected palette channel.
- Each replacement differs from the previous value, including between locales.
- Closing and reopening Settings does not create extra groups.

The test does not call the well's action itself. AppKit forwards color-panel changes to the active well.
The assertions read the production preference getters after that interaction.
They cover 36 independent native color-panel edits across the six panes.

Run from the repository root:

```sh
python3 Tests/ViewControlsReview/run-probe.py \
  --probe Tests/UserSchemeReview/round1/contrarian/probe.inc \
  --prefix Tests/UserSchemeReview/round1/contrarian/prefix.h \
  --app build/UserSchemeReview/initial/nvALT.app
```

Result: **242 checks passed**, including two library setup checks. See `output.txt`.
An initial development run also passed. The final probe varies replacement colors between locales to exclude no-op edits.

Reviewed production commit: `3297f6e`, compared with `78d9442`.
Application SHA-256: `8060f1cb71a119e94bce789df38494c100719eaf744a4fb72df9684f7f7858f1`.
Host: macOS 26.5.2, Xcode 26.6, Intel app under Rosetta.
The runner uses a copied app, a separate preferences domain, and disposable notes.

## Limits

This probe selects each nib explicitly. It does not test macOS language selection or translate the newly added strings.
Geometry checks use native view bounds and cell sizes. They do not establish pixel appearance on every display size or OS release.
Color-panel changes use public AppKit methods rather than physical mouse input.
Controllers remain retained for the run; this test does not establish controller deallocation behavior.

## PR comment

Round 1 — Contrarian perspective: no actionable finding in the Settings layout or color-panel routing. I wrote and ran a native probe that loads all six localized compiled Preferences nibs. It checks group, label, and well geometry; performs 36 edits through the shared native color panel; verifies that only the active palette channel changes; and closes/reopens each Settings pane. All 242 checks passed. The probe selects nibs explicitly and uses public AppKit calls, so it does not establish OS language selection, physical mouse behavior, or compatibility with older macOS versions. Evidence: `Tests/UserSchemeReview/round1/contrarian/`.
