# Round 2 — Dan Luu perspective

This review uses an empirical engineering perspective inspired by Dan Luu. It does not represent his authorship or endorsement.

**[P2] Resolve named search-highlight colors under the editor's appearance.**

The finding was at `Sources/Editor/LinkingEditor.m:473–477` in `0fc7aca`, before the Round 2 fix.
The new helper chose the correct raw dark preference, but converted its named color without an appearance scope.
Asynchronous search completions run outside drawing. On this host, that conversion used Aqua even when the app and both windows used Dark Aqua.

The native Color Panel exposes `selectedTextBackgroundColor` in the System color list.
Choosing it for the new Dark Search Highlight slot preserved the catalog color through the well action and archived preference.
After an application appearance change to Dark Aqua, Exact search drew the light variant in both windows.
The expected RGB was `(0.192056, 0.310345, 0.470728)`; the actual RGB was `(0.646331, 0.802616, 0.999209)`.
The foreground and background resolved correctly in the same windows.

This needs an appearance scope around the highlight conversion, with a compatible fallback on older macOS releases.

## Independent evidence

I read all five Round 1 reports before selecting this gap. Those probes covered fixed RGB, grayscale, CMYK, and alpha endpoints.
They did not exercise an appearance-dependent native catalog color in the new dark highlight slot.

The test opens two native browsers over one note. Their `appearance` properties remain unset, so both inherit the application appearance.
It opens Settings, activates the Dark Search Highlight well, and changes the shared native Color Panel from red to the System named color.
It checks the archived preference's catalog identity after AppKit dispatches the change. It does not call the well action directly.
The test alternates native application appearance four times, and waits for real asynchronous Exact-search decorations.

| Evidence | Result |
| --- | --- |
| Pre-fix production path, [output.txt](output.txt) | 22 passing assertions, four dark appearance mismatches, then expected exit 1 |
| Same app with scoped publication control, [scoped-control.txt](scoped-control.txt) | 27 assertions passed; exit 0 |
| Compiled production fix, [fixed-output.txt](fixed-output.txt) | 27 assertions passed; exit 0 |
| Native color inventory, [inventory.txt](inventory.txt) | System list contains the selected catalog color |
| Retained historical helper, [legacy-observation.txt](legacy-observation.txt) | Four assertions passed; the legacy light helper has the same unscoped limitation |

Counts include two temporary-library setup checks.

The scoped control wraps the unchanged `setSearchHighlightRanges:` method in the editor's drawing appearance.
It changes no saved preference, search result, or color formula. The original app then passes every color assertion.

The production probe is now maintained in [dynamic-colors.inc](../../../Regression/user-schemes/dynamic-colors.inc) and [dynamic-colors.h](../../../Regression/user-schemes/dynamic-colors.h).
The review [probe.inc](probe.inc) includes that code. The review [prefix.h](prefix.h) adds the optional control only.

## Fix verification

The root agent changed `currentSearchHighlightAttributes` to resolve colors under `effectiveAppearance`.
The helper retains its result inside that scope, then returns it autoreleased.
It uses the macOS 11 API when available and restores the earlier appearance through `@try`/`@finally` on older systems.

The same production probe passed after rebuilding. No control environment variable was set.
Both windows produced the correct named highlight in light and dark appearances, and shared source attributes remained unchanged.
I found no remaining actionable defect in this path.

## Historical scope and limits

The old `searchTermHighlightColorRaw:NO` implementation at upstream `78d9442` also converts named colors without an appearance scope.
The `legacy.inc` observation calls that unchanged method in the same pre-fix binary. It is not a separate upstream build.
The general named-color limitation therefore predates this PR. This finding concerns its extension to the newly added dark preference slot.

The test changes the application's native appearance while the desktop remains light. It does not change the user's macOS preference.
It establishes the editor's effective-appearance contract, not every schedule of global system preference changes.
Color-panel edits use public AppKit methods, not physical mouse input. The native System list is present on this host.
The assertions inspect actual temporary drawing attributes; they do not compare screenshot pixels.
The note is small, so these results establish correctness, not long-note performance.

An initial half-alpha fixture was unsuitable: `colorWithAlphaComponent:` resolved that native color to fixed RGB on this host.
The final fixture retains the original named color and first checks that its light and dark resolved values differ.

## Commands and environment

```sh
# Reproduce against the frozen pre-fix app.
python3 Tests/ViewControlsReview/run-probe.py \
  --app build/UserSchemeReview/compatibility-fixed/nvALT.app \
  --probe Tests/UserSchemeReview/round2/luu/probe.inc \
  --prefix Tests/UserSchemeReview/round2/luu/prefix.h

# Isolate the missing appearance scope in that same app.
LUU_SCOPED_HIGHLIGHT_CONTROL=1 python3 Tests/ViewControlsReview/run-probe.py \
  --app build/UserSchemeReview/compatibility-fixed/nvALT.app \
  --probe Tests/UserSchemeReview/round2/luu/probe.inc \
  --prefix Tests/UserSchemeReview/round2/luu/prefix.h

# Verify the compiled fix without the control.
python3 Tests/ViewControlsReview/run-probe.py \
  --probe Tests/UserSchemeReview/round2/luu/probe.inc \
  --prefix Tests/UserSchemeReview/round2/luu/prefix.h
```

The inventory and historical observations use the same runner and prefix, with `inventory.inc` or `legacy.inc` as the probe.
All runs use a copied app, disposable notes and preferences, and the shared GUI lock.

Host: macOS 26.5.2, Xcode 26.6, Intel app under Rosetta.

- Pre-fix source: `0fc7aca`; executable SHA-256: `0e877e5a1576b932b6bedfb85770a918f266925f0cc844120cce0987a889f695`.
- Corrected source: `da052b2`; executable SHA-256: `3e8ebdc2258bd0d402e56066e6dd649ed7c277b4c6b05f95566a7e468df0dbf9`.

## Proposed PR comment

Round 2 — Dan Luu-inspired empirical review: **[P2] resolve named highlight colors under the editor's appearance**, found and fixed. A native System catalog color selected through Settings' Dark Search Highlight well kept its light RGB after the app switched to Dark Aqua. Two browsers produced four mismatches. A scoped-publication control passed 27 assertions on the same app; the compiled production fix passed the same 27 without instrumentation. The named-color limitation also exists in the historical light helper, but this PR added the affected dark slot. The probe sets native application appearance rather than changing the desktop preference. Evidence and maintained regression links: `Tests/UserSchemeReview/round2/luu/report.md`.
