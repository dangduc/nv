# Round 1 — Dan Luu perspective

This review uses an empirical engineering perspective inspired by Dan Luu. It does not represent his authorship or endorsement.

No actionable PR defect found in this review.

## Scope and evidence

Reviewed the User Scheme change against `upstream/master` (`78d9442`). The application change is committed as `3297f6ec7f444f932a0a1049b3241c41eb18ea44`.
The tested Intel executable has SHA-256 `8060f1cb71a119e94bce789df38494c100719eaf744a4fb72df9684f7f7858f1`.
The host runs macOS 26.5.2 and Xcode 26.6, with the Intel app under Rosetta.

The maintained suite sets each window's appearance and uses Plain Text. This independent probe tests inherited application appearance with syntax highlighting.
Two native browser windows share each of three notes: Markdown, HTML, and JSON. Neither window has its own appearance override.
The probe sets the application's native appearance six times per grammar. It does not call `browserAppearanceChanged` itself.

All **148 assertions passed**, including the runner's two setup checks. The evidence establishes:

- Both windows inherit each light or dark application appearance and select the matching User Scheme background.
- Ordinary glyph attributes use the selected foreground. Existing syntax captures remain current and use different light and dark drawing colors.
- All three grammars retain shared text storage. No source or model attributes change during recoloring.
- Six appearance changes per grammar cause zero additional parser calls and leave the highlighter generation unchanged.

The parser instrumentation increments one atomic counter and calls the original method. It does not change parser results.

Relevant code: `Sources/Browser/AppController_BrowserUI.m:395–417` chooses and applies the palette. Existing `Sources/Editor/LinkingEditor.m:405–438` resolves syntax colors during drawing.

## Reproduction

```sh
python3 Tests/ViewControlsReview/run-probe.py \
  --probe Tests/UserSchemeReview/round1/luu/probe.inc \
  --prefix Tests/UserSchemeReview/round1/luu/prefix.h
```

Exit status: **0**. See [probe.inc](probe.inc), [prefix.h](prefix.h), and [output.txt](output.txt).
The runner uses a copied app, temporary notes and preferences, and the shared GUI lock.

## Limits

The probe changes native application appearance, not the user's macOS preference. It calls native window display, then inspects the layout manager's drawing attributes.
It does not compare screenshot pixels or measure the display compositor.

The six-transition observations were 861.515 ms for Markdown, 750.446 ms for HTML, and 744.470 ms for JSON.
Each sequence includes six explicit 100 ms run-loop waits. These numbers are observations, not a latency benchmark.
The small notes and two windows do not establish performance on large libraries or long notes.

## Proposed PR comment

Round 1 — Dan Luu-inspired empirical review; no actionable finding. Independent native evidence passed 148 assertions across Markdown, HTML, and JSON. Two windows without appearance overrides inherited six application light/dark changes per grammar. Ordinary glyphs changed palettes, syntax glyphs stayed colored, shared source/model attributes stayed unchanged, and parser instrumentation observed zero extra parses during recoloring. This tests native appearance inheritance and drawing attributes; it does not measure compositor latency or change the user's system preference. Evidence: `Tests/UserSchemeReview/round1/luu/`.
