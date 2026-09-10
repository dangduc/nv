### Round 2 — John Ousterhout-inspired review

No actionable source API or ownership defect found at `4dab02a`.

I wrote and ran a copied-app probe against production methods: **144 assertions passed**, including four isolation checks.
The count includes repeated assertions across six syntax choices and two menus.

The menu, popup, and model choices agree. Invalid API input selects Plain Text and sends one effective-change notification.
Syntax changes preserve unrelated metadata, source, dates, filenames, Undo history, and the independent preview choice.
An unopened note restores Org by UUID. Its first session creates correct Org links before any layout attaches.
Later syntax changes refresh those links. Session closure removes the observer.

The existing duplicate syntax lists remain consistent. I found no defect that requires a registry refactor in this PR.

Evidence: `Tests/OrgSourceReview/round2/ousterhout/{run.py,probe.inc,output.txt,evidence.json,report.md}`.
The run used macOS 26.5.2, Xcode 26.6, and the Intel app through Rosetta.
It does not cover parser fidelity, scanner state, highlighting performance, rendered preview, or visible-editor Undo.
