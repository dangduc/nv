# Round 1 — contrarian review

The review challenges the assumption that removing title-bar controls preserves access to their behavior.
It accepts the requested search-only design and does not propose restoring its removed icons.
No actionable regression was found in the tested search, accessibility, or hidden-header interactions.

Reviewed production commit: `6b8d67514f4fc5bc2e9fca22816a32f30f59fb1c`, against upstream `89d9abe`.
Relevant changes are in `Sources/Browser/AppController_BrowserUI.m:343` and `Sources/Browser/AppController.m:2013`.

## Executable evidence

Run `python3 Tests/TitlebarReview/round1/contrarian/run.py` from an active desktop session.
The runner uses the actual Intel Development app and the existing copied-app harness.
It creates disposable notes, isolates preferences, and acquires `build/pr-review/gui.lock` before each launch.

The production probe passed 38 assertions on macOS 26.5.2 with Xcode 26.6.
It hides the title, tags, source/preview controls, and notes list, then uses a 480-point content width.

| Scenario | Observed result |
| --- | --- |
| Search for `tousand` in a note body containing `thousand` | Exact returns zero rows; the native Fuzzy menu command returns the one matching note. |
| Switch back to Exact | The query remains unchanged; the fuzzy-only row disappears. Exactly one mode item remains checked. |
| Search accessibility | The accessible label follows the selected mode. The new container exposes the native search cell with `AXTextField` / `AXSearchField`. |
| Native clear button | Both search strings become empty; the note count remains unchanged. |
| Selected note title | Its visual title remains hidden; the window's accessibility title retains its note identity and follows later selection changes. |
| Tab, with all note controls hidden | Focus reaches editable source. |
| View menu, with its icon and header toggle absent | Preview opens, then Source regains editing focus. |
| Return on an unmatched query | One note is created with the query as its title; editable source receives focus. |
| Original note sources | Both retain their exact characters. |

The negative control clears only the semantic window title after selecting a note.
It passes the preceding 26 assertions and fails the expected accessibility-title assertion.
This shows that the title test detects a lost note identity despite the visual title being intentionally hidden.
The Exact/Fuzzy fixture also supplies a behavioral negative control for mode selection.

## Identity and limits

| Input | SHA-256 |
| --- | --- |
| `AppController_BrowserUI.m` | `6a179cb93dfe10052bb894b077cb969a1a748862646adbe35cec4b4cdcf1a33a` |
| `AppController.m` | `46a9c9f6f0aee838d547dd7b0ef17fa80f97978e1e951ffa0dca91229dac67be` |
| `AppController_Search.m` | `c9140868ba8ff918e47f420bf7a33efed22232ec4bdcf77be075fbbad92f6a68` |
| `DualField.m` | `6617a4b656f5d55587ac0ee374148efdbc906772c9f3e2ace1ab9a205dd6f9c8` |
| Development executable | `5b672807c892a9e12b8b1ce8291f17853bb93780cd4caf80946885198e47d8ca` |

The runner verifies that its production source inputs still match the reviewed commit.
Raw logs, result counts, and hashes are written under `build/TitlebarReview/round1/contrarian/`.
Review-record commits advanced the checkout during this review; the production input hashes stayed unchanged.

The harness dispatches native menu actions and field-editor commands; it does not synthesize menu mouse clicks.
Accessibility checks inspect AppKit's exposed elements and attributes, not a full VoiceOver session.
It does not test older macOS versions, full-screen presentation, or Window-menu navigation.

Two initial fixture mistakes were corrected before the final run: a preference setter omitted its `sender:` argument,
and the first accessibility assertion inspected the ignored search view instead of its exposed search cell.
Diagnostic logs preserve both failures. Neither required a production change.
