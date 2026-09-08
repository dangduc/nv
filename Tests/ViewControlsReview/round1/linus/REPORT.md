# Round 1: Linus Torvalds-inspired review

Reviewed PR #5 at `162c872`. This review uses a correctness-focused perspective. It does not represent Linus Torvalds or his endorsement.

No actionable finding was confirmed.

The independent native probe passed 67 checks against the frozen application build. The source-nib audit passed for all six localizations.

The probe rebuilt the new menu entries after it replaced the anchor title with French and Japanese text.
Four calls to `configureMenus` preserved the exact action order, unique entries, coordinator targets, and five syntax identifiers.
The Word Count item retained no obsolete value binding.

In Preview, hiding an untouched title field or tag field transferred keyboard focus into the viewer.
Hiding the focused Preview format popup also transferred focus into the viewer.

Three toolbar histories removed Search, restored Search, waited for its visible field editor, and transferred focus to Source.
A subsequent header visibility change retained Source focus through ten run-loop iterations.
These histories did not reproduce the earlier fixture focus failure.

Run the evidence:

```sh
python3 Tests/ViewControlsReview/round1/linus/audit-locales.py
python3 Tests/ViewControlsReview/run-probe.py \
  --app build/ViewControlsReview/round1/nvALT.app \
  --probe Tests/ViewControlsReview/round1/linus/probe.inc
```

Both commands returned zero. Results are in `locales-output.txt` and `native-output.txt` beside this report.
The native runner uses a copied application, disposable notes, a unique preferences domain, and the shared GUI lock.

The locale audit checks XML action anchors. It does not launch six localized applications or assess translation quality.
The keyboard probe uses a 780-point window and native responder calls. It does not cover every toolbar width or pending Search animation.
