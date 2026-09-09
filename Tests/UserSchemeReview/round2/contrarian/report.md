# Round 2: contrarian review

No actionable defect found in the global highlight toggle or active color-panel routing.

This round uses a contrarian engineering perspective. It does not attribute the review to another person.
I read the first-round reports before choosing this test.
Round 1 tested localized layouts and used direct editor decoration calls for the four-scheme matrix.
This probe instead follows a real Exact search and the native Settings checkbox while the color panel remains active.

## Evidence

The fixture opens two real browsers on one note with opposite light and dark appearances.
Both browsers run Exact search for a word present in the title and body.
The test waits for the resulting source decorations; it does not install decoration ranges.

It opens Fonts & Colors and clicks the global Highlight Search Terms checkbox with `performClick:`.
After highlights disappear, the test activates the dark highlight well through `NSColorWell.activate:`.
It changes Settings appearance four times and edits the active well through `NSColorPanel.setColor:` each time.
It also changes both browser appearances while highlights remain disabled.

The assertions establish these results:

- The checkbox removes real source decorations from both browsers.
- Settings appearance changes retain the active dark color-well target.
- Four actual dark edits change only the dark highlight preference.
- Palette edits and browser appearance changes preserve the disabled highlight preference and absent decorations.
- Switching the color panel to the light well changes only the light highlight.
- Re-enabling highlights uses the latest separate colors in both browsers.
- The global toggle remains effective across Black & White and User Scheme changes.
- The shared source attributes and stored source text stay unchanged.

Run from the repository root:

```sh
python3 Tests/ViewControlsReview/run-probe.py \
  --probe Tests/UserSchemeReview/round2/contrarian/probe.inc \
  --prefix Tests/UserSchemeReview/round2/contrarian/prefix.h
```

Result: **38 checks passed**, including two library setup checks. Exit status: 0. See `output.txt`.

Reviewed production commit: `0fc7aca`, which includes the compatibility correction from Round 1.
Application SHA-256: `0e877e5a1576b932b6bedfb85770a918f266925f0cc844120cce0987a889f695`.
Host: macOS 26.5.2, Xcode 26.6, Intel app under Rosetta.
The runner uses a copied app, disposable notes, and a separate preferences domain.
No application source changed during this review.

## Limits

The probe uses public AppKit calls rather than physical mouse input.
It changes native window appearances, not the user's system appearance setting.
It tests Exact search with one small plain-text note. It does not measure fuzzy-search scheduling or large-note performance.
It checks native temporary attributes rather than screenshot pixels.
The test uses opaque calibrated colors; named system-color resolution is covered by another review.

## PR comment

Round 2 — Contrarian perspective: no actionable finding. I wrote and ran a native probe around the global Highlight Search Terms checkbox and an active color panel. Across two real Exact-search views, disabling highlights survives five palette edits and browser appearance changes. The active dark well stays bound to its dark channel while Settings appearance changes. Re-enabling highlights uses the latest independent colors, and the toggle also works across Black & White and User Scheme changes. All 38 checks passed; source attributes and stored text stayed unchanged. The probe uses public AppKit calls and native temporary attributes on macOS 26.5.2. Evidence: `Tests/UserSchemeReview/round2/contrarian/`.
