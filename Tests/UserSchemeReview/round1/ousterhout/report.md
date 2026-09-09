# Round 1: Ousterhout engineering perspective

This review uses an engineering perspective inspired by John Ousterhout. It does not claim his authorship or endorsement.

No actionable PR defects found.

I reviewed the change against `upstream/master` at `78d9442fac207022a046108340b94fcb01d74b04`.
I read `architecture.md` and the browser, editor, preference, and Settings changes.
The focus was the boundary between raw application preferences and colors resolved for each browser.

## Evidence

The independent native probe passed **108 checks**, including three setup checks.
It used a copied app, disposable notes and preferences, and two real browser windows.

```sh
python3 Tests/ViewControlsReview/run-probe.py \
  --probe Tests/UserSchemeReview/round1/ousterhout/probe.inc \
  --prefix Tests/UserSchemeReview/round1/ousterhout/prefix.h \
  > Tests/UserSchemeReview/round1/ousterhout/output.txt 2>&1
```

The command exited with status 0.
See [probe.inc](probe.inc), [prefix.h](prefix.h), and [output.txt](output.txt).

The probe routes all four existing Color Scheme actions through the application coordinator.
For each scheme, it changes both windows through opposite light and dark appearances, including both high-contrast variants.
This exercises 32 browser states over one shared note.

The checks establish these results:

- Black & White and Low Contrast retain their configured colors after appearance changes.
- User Scheme selects the matching custom palette in each browser. System Scheme continues to use that browser's resolved system colors.
- Editor search decorations use the applicable raw highlight and the actual browser background. Both windows keep independent temporary attributes.
- Scheme and appearance changes preserve the shared source attributes and the six raw preference values used by the probe.
- A dark highlight edit produces a fresh result while an earlier retained result stays unchanged. Legacy highlight accessors retain their light-palette behavior.

The raw values are set through the preference API before the matrix runs.
The final preference assertion checks four foreground/background values; highlight preservation is checked through the final legacy and retained-result assertions.

## Analysis

`GlobalPrefs` retains raw palette ownership. `AppController` selects the palette using its window's appearance.
`LinkingEditor` supplies the browser background when it requests highlight attributes.
The two-window matrix supports this division of responsibility and checks compatibility with the other schemes.

Palette selection appears in the initial getters and the appearance callback.
That duplication is small and currently consistent. I found no demonstrated behavior failure that requires another abstraction in this PR.

The Settings code reuses localized nib controls and centralizes group construction in one helper.
I reviewed its ownership and refresh paths. I found no concrete lifetime or callback defect in the diff.

## Environment and limits

- macOS 26.5.2, Xcode 26.6; Intel app under Rosetta.
- App SHA-256: `8060f1cb71a119e94bce789df38494c100719eaf744a4fb72df9684f7f7858f1`.
- The probe changes each window's native appearance. It does not change the desktop's global appearance preference.
- Search ranges are installed directly through the editor API. This isolates palette resolution from asynchronous search timing.
- The probe does not assess Settings layout, localization, restart persistence, rendering cost, or older macOS versions.
- The compiler reports an availability warning for the probe's system-color oracle. The runtime host supports that API.
- No application source changed during this review. Existing broad-suite failures were not used as evidence about this PR.

## Proposed PR comment

Round 1 — Ousterhout engineering perspective, not authorship or endorsement: no actionable findings.

An independent native probe passed 108 checks across two browsers and all four Color Schemes.
It covers opposite light/dark and high-contrast appearances, browser-local highlight blending, shared source preservation, and legacy light preference behavior.
Retained decoration dictionaries also remain unchanged after a dark highlight edit.

Evidence: `Tests/UserSchemeReview/round1/ousterhout/`.
The probe installs decoration ranges directly and runs on macOS 26.5.2; it does not validate asynchronous search timing or older systems.
