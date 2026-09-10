### Round 1 — John Ousterhout-inspired review

No actionable viewer-boundary or ownership defect found at `4467e7a`.

I wrote and ran a native copied-app probe: **72 assertions passed**, including four launch-isolation checks.
The assertions include repeated checks across four formats and two helper failure cases.

Menus, the popup, renderer dispatch, and saved-window restoration agree on Org.
Org preview works with Plain Text source metadata and preserves the shared source editor in the peer window.

I removed the converter only from the disposable app, then installed a fixture that exits with status 27.
Both failures show an error, hide the prior document, clear the export result, and disable export, print, and viewer Find.
Source, caret, generation, dates, and Undo state remain unchanged.
Restoring the actual helper allows a successful Org retry through the same browser.

Evidence: `Tests/OrgPreviewReview/round1/ousterhout/{run.py,probe.inc,output.txt,evidence.json,report.md}`.
The run used macOS 26.5.2, Xcode 26.6, and the Intel app through Rosetta.
It does not cover a full app relaunch, broad Org fidelity, large-note performance, composition, or Undo after source edits.
