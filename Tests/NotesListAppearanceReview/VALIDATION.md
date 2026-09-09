# Notes list appearance validation

Host: macOS 26.5.2 (25F84), Xcode 26.6 (17F113), Apple Silicon.

The Development Intel build passed with the command in `AGENTS.md`.
The build retains existing compiler and analyzer warnings.
The focused `Tests/Regression/native-list/run-native.py --negative-control` command passed 38 checks.
Its negative control detected missing tag words with the obsolete compositing operation.
The native UI integration harness compiled for arm64 and x86_64 without diagnostics.

The focused fixture draws the production preview formatter and extracted tag-image method with fixed font preferences.
It checks the same cached text and shared image cache through light, dark, and light appearances.
It checks ordinary and selected text, tag colors, and visible tag words.
Its screenshots show sample rendering, not a complete browser window.

![Light rendering fixture](../../docs/screenshots/notes-list-light-fixture.png)

![Dark rendering fixture](../../docs/screenshots/notes-list-dark-fixture.png)

Full desktop tests remain blocked by the host's existing Intel startup stall.
The earlier disposable Intel probes remain in an uninterruptible state before application startup.
They were still present during this change's validation.
No additional Intel application probes were launched.
The focused fixture does not establish full browser lifecycle, keyboard-focus, or live system-notification behavior.

## Review validation

Both review rounds completed with no actionable introduced finding.
All ten native review runners passed together with desktop access.
The command was `python3 Tests/NotesListAppearanceReview/run.py`.
The combined log is `build/notes-list-final-review-regressions.log`.

The round-one aggregate exposed a Retina scale assumption in one review fixture.
The delegated correction compares tag and mask images at matching native backing dimensions.
It preserves the original alpha tolerance and still rejects the obsolete compositing operation.
This correction changed only review evidence.

Round two adds native active selection, field-editor focus, hidden-window callbacks, controller recreation, and production tag-consumer drawing at 1×/2×.
Each [review report](README.md) states which production methods and fixture collaborators it uses.
The active-selection fixture records a light inline-editor observation that also occurs with the base source.
It does not establish an introduced defect or the full production inline-edit behavior.

Production remains unchanged from `2e3f75e794b668024cf54597110f13ccf2aff97a`.
The successful local Intel build therefore covers the production source in both review rounds.
The shipping Intel application and complete desktop suites remain blocked by the startup stall described above.
