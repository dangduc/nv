Round 1 — Linus Torvalds-inspired review (engineering perspective, not authorship or endorsement).

**[P1] Preserve User Scheme support before macOS 11 — `Sources/Browser/AppController_BrowserUI.m:406`.**

The PR now routes User Scheme through `browserAppearanceChanged`. That method guards `performAsCurrentDrawingAppearance:` at macOS 10.14, but the SDK declares it macOS 11+. User Scheme can now raise an unrecognized-selector exception on supported macOS 10.14/10.15. The incorrect guard already affected System. This PR extends it to User Scheme. Use a macOS 11 guard and a save/set/restore `currentAppearance` fallback for earlier systems.

I wrote and ran an unavailable-selector simulation in the copied native app. The current User Scheme action failed. The pre-change method body passed under the same simulation. This evidence checks the call path, not an actual older macOS installation.

An independent 35-check probe passed. It covers raw light archive preservation, registration-only dark defaults, nil setters, color ownership, highlight alpha endpoints, and fixed/System scheme compatibility.

Evidence: `Tests/UserSchemeReview/round1/torvalds/` contains both probes, their output, and the full report. Host: macOS 26.5.2, Xcode 26.6, Intel app through Rosetta.
