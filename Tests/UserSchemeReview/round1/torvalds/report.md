# Round 1 — Torvalds perspective

This review uses a Linus Torvalds-inspired engineering perspective. It does not represent his authorship or endorsement.

**[P1] Preserve User Scheme support before macOS 11.**

Location: `Sources/Browser/AppController_BrowserUI.m:406`.

The PR routes `setUserColorScheme:` through `browserAppearanceChanged`.
That method calls `performAsCurrentDrawingAppearance:` under a macOS 10.14 availability guard.
The Xcode 26.6 SDK declares this selector with `API_AVAILABLE(macos(11.0))` in `AppKit.framework/Headers/NSAppearance.h:36`.
The project still supports macOS 10.13.

On macOS 10.14 and 10.15, User Scheme now reaches an unsupported selector.
An absent selector raises an exception during scheme selection or an appearance update.
The previous User Scheme method set the colors and called `updateColorScheme` directly.
System already used the incorrect guard. This PR extends that existing defect to User Scheme.

Use a macOS 11 guard for the new API.
For earlier systems, preserve the current appearance, set the browser appearance, apply the colors, and restore the previous appearance.

The executable simulation replaces the selector with `doesNotRecognizeSelector:` only during the scheme action.
The current User Scheme action failed with an unrecognized-selector exception.
The pre-change method body passed in the same binary under the same simulation.
This control preserves the old implementation from upstream `78d9442`, with a renamed selector and whitespace changes.

| Evidence | Result |
| --- | --- |
| [General probe](probe.inc), [prefix](prefix.h), [output](output.txt) | 35 checks passed, including two setup checks |
| [Availability probe](availability.inc), [prefix](availability-prefix.h), [output](unavailable-selector.txt) | Expected failure: current User Scheme calls the unavailable selector |
| [Legacy control output](legacy-control.txt) | Four checks passed, including two setup checks |

The general probe checks archived grayscale and CMYK light colors without rewriting their bytes.
It also checks registration-only dark defaults, nil setters, callback silence, retained color ownership, and transparent/opaque highlight endpoints.
Fixed schemes and System retain their selection and colors across native appearance changes.

Commands:

```sh
python3 Tests/ViewControlsReview/run-probe.py \
  --probe Tests/UserSchemeReview/round1/torvalds/probe.inc \
  --prefix Tests/UserSchemeReview/round1/torvalds/prefix.h

python3 Tests/ViewControlsReview/run-probe.py \
  --probe Tests/UserSchemeReview/round1/torvalds/availability.inc \
  --prefix Tests/UserSchemeReview/round1/torvalds/availability-prefix.h

NV_LEGACY_USER_SCHEME=1 python3 Tests/ViewControlsReview/run-probe.py \
  --probe Tests/UserSchemeReview/round1/torvalds/availability.inc \
  --prefix Tests/UserSchemeReview/round1/torvalds/availability-prefix.h
```

Host: macOS 26.5.2, Xcode 26.6, Intel app through Rosetta.
App SHA-256: `8060f1cb71a119e94bce789df38494c100719eaf744a4fb72df9684f7f7858f1`.

The simulation checks the new call path. It does not run an actual macOS 10.14 or 10.15 system.
The general probe does not establish leak freedom or compatibility with every archived color class.
Production files remained unchanged during this review.
