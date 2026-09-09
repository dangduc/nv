# Round 1: Contrarian workflow review

Baseline: `2e3f75e794b668024cf54597110f13ccf2aff97a`, compared with `878961a`.

No actionable regression was found in this review scope.

The independent probe uses native `NSTableView`, `NSTextFieldCell`, `NSScrollView`, and `NSWindow` instances.
It compiles the production preview formatter and extracts the production loading-text initialization, table drawing method, and cell-color delegate method.
The fixture supplies three temporary rows and the ordinary-list preview selection policy.
It does not load the application or a notes library.

`python3 Tests/NotesListAppearanceReview/round1/contrarian/run.py --negative-control` passed 242 assertions on the native arm64 host.
The probe captured 48 populated rows across Aqua and Dark Aqua, plain and alternating backgrounds, previews on and off, and inactive selection.
Title and preview glyphs contrasted with each captured row background.
The four loading states and four empty states retained the appropriate appearance.
These captures use the native view drawing context, without an explicit appearance block around table drawing.

A negative control restores the former translucent black loading-text color.
That control failed the dark loading-text glyph assertion.
This establishes that the fixture detects this specific dark-mode regression.
The normal source was restored and the probe was rebuilt after the control.

The optional legacy scroller did not demonstrate an invisible knob.
The probe compiles the production `ETOverlayScroller` and `ETTransparentScroller` implementations and loads their six actual image resources.
It draws their knob and track methods over the new system background.
The measured center-to-background brightness difference was 0.3137 in Aqua and 0.1725 in Dark Aqua.
This is a pixel observation, not an accessibility contrast guarantee.
The fixture uses the legacy scroller style. Overlay fading and mouse tracking remain outside this result.

The selected-row captures use inactive native windows.
Active application selection, field editing, actual nib initialization, and live system appearance notifications remain outside this fixture.
A simulated key-window state produced an inconsistent native selection background, so that experiment supplies no application defect claim.
The Intel application was not launched because the host has the documented startup stall.

Outputs are in `build/NotesListAppearanceReview/round1/contrarian/`.
The compiler emitted the existing `BufferUtils.c:406` pointer-cast warning.
There were no production changes.
