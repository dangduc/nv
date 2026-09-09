# Round 2 — contrarian review

No actionable regression was found in native Window-menu routing or the tested accessibility structure.
This round examines boundaries not covered by the first round's single-window command checks.
It accepts the requested search-only title bar.

Reviewed production: `6b8d67514f4fc5bc2e9fca22816a32f30f59fb1c`.
PR checkout during the run: `2566d427ba3d7ace7e12b672bf6ab0fd5f08d845`.
The source hashes match the reviewed production commit and remain unchanged before and after both runs.

## Three-window evidence

Run `python3 Tests/TitlebarReview/round2/contrarian/run.py` from an active desktop session.
The copied Intel app uses disposable notes and isolated preferences.
The existing harness acquires `build/pr-review/gui.lock` before each native launch.

The production run passes 48 assertions on macOS 26.5.2 with Xcode 26.6.
Two windows select different notes with the same title, `Identical note name`.
A third selects a note whose title contains 1,033 UTF-16 code units, including Japanese characters and an emoji.
The three windows retain different body queries: `corpus alpha`, `corpus beta`, and `corpus gamma`.

| Boundary | Observed result |
| --- | --- |
| Complete window accessibility tree | Each window has 30 exposed descendants, including exactly one search cell belonging to that browser. |
| Accessible parent navigation | The exposed search cell appears in its parent's child list. The layout wrapper adds no accessible element or keyboard focus stop. |
| Accessibility focus through the native search control | `setAccessibilityFocused:YES` opens that browser's native field editor without changing its query. |
| Window menu with identical titles | Both menu items retain separate window targets. Dispatching both activates two different windows. |
| Window menu with a long Unicode title | The menu retains its complete title; dispatch activates the correct window and application command receiver. |
| State after Window-menu navigation | All three browsers preserve their selected note, session query, and visible search text. |

The negative control redirects a duplicate-title menu item's target to the third window.
It passes 39 preceding assertions, then fails the expected window-identity assertion.
This detects incorrect routing even when both legitimate destination windows have identical labels.

## Accessibility focus investigation

An initial assertion attempted to focus the exposed `NSSearchFieldCell` directly after enumerating the complete accessibility tree.
The cell advertised a writable focus attribute, but that setter left the source editor focused.

`focus-control.inc` isolates this observation in the PR app, the unchanged baseline app, and a stock `NSSearchField`.
Both app runs pass five fixture and direct-focus checks. All six measured focus paths per app show the same result:

| Setter after tree enumeration | Production search | Stock search |
| --- | --- | --- |
| Cell's legacy accessibility setter | Editor remains unfocused | Editor remains unfocused |
| Cell's protocol accessibility setter | Editor remains unfocused | Editor remains unfocused |
| Search control's protocol accessibility setter | Native field editor receives focus | Native field editor receives focus |

The unchanged baseline at `66beeb9` reproduces this matrix; its source tree matches upstream `89d9abe`.
The first diagnostic, before adding tree enumeration, allowed all three setters to focus both fields.
These controls support treating the initial failure as an in-process AppKit interaction limit, not a regression introduced by the toolbar wrapper.
The final main probe uses the public search-control setter and records the cell-level observation separately.

Reproduce the comparison with `python3 Tests/TitlebarReview/round2/contrarian/run-focus-control.py`.
It accepts `--baseline-app` if the unchanged app was built elsewhere.

## Identity and limits

| Input | SHA-256 |
| --- | --- |
| `AppController_BrowserUI.m` | `6a179cb93dfe10052bb894b077cb969a1a748862646adbe35cec4b4cdcf1a33a` |
| `AppController.m` | `46a9c9f6f0aee838d547dd7b0ef17fa80f97978e1e951ffa0dca91229dac67be` |
| `AppController_Search.m` | `c9140868ba8ff918e47f420bf7a33efed22232ec4bdcf77be075fbbad92f6a68` |
| `DualField.m` | `6617a4b656f5d55587ac0ee374148efdbc906772c9f3e2ace1ab9a205dd6f9c8` |
| Development executable | `5b672807c892a9e12b8b1ce8291f17853bb93780cd4caf80946885198e47d8ca` |

Logs, before/after hashes, and result counts are in `build/TitlebarReview/round2/contrarian/`.
Menu items are dispatched through their actual targets and actions; the probe does not synthesize menu mouse clicks.
The duplicate labels remain visually identical. This test proves separate routing, not visual disambiguation between those labels.
Accessibility checks use AppKit objects and setters, not an external VoiceOver or assistive-technology session.
They establish that the wrapper adds no focus stop; they do not establish every VoiceOver traversal order.
Older macOS versions, Spaces, and full-screen behavior are outside this review.
