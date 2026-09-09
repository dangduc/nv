# Round 1: contrarian review

No actionable findings in commit `504f303` against `b289ba3`.

The review challenged whether the title came from literal live input, a submitted query, selected text, or an existing matched note.
It also challenged whether a duplicate title would accidentally reuse the original note.
The product contract remains the user's request: focused, nonempty Search supplies the complete title.

Reviewed paths:

- `Sources/Browser/AppController_BrowserUI.m:319` captures the complete field editor string before editing ends and Search clears.
- `Sources/Browser/AppController_Search.m:14` requires the key window and its active Search editor.
- `Sources/Browser/AppController.m:1598` keeps the existing implicit-creation wrapper.
- `Sources/Browser/AppController.m:1613` falls back only for an empty title.
- `Sources/Model/NoteObject.m:950` copies the title without applying search parsing or normalization.

## Executable evidence

`probe.inc` invokes Command-N through the application's real menu in a copied app with a disposable library.
It uses literal expected strings, independent of the submitted query and result title.
The production implementation passed **23 assertions**, including setup checks (`run.log`, exit 0).

The probe covers:

- A live title with leading/trailing spaces, quotes, emoji, a decomposed accent, and query-like punctuation.
- A selected substring within the field; the complete field text becomes the title.
- A stale submitted query that differs from the live field editor.
- Creation of a distinct note with an already-existing title.
- Preservation of the original title and body, an empty new body, and cleared Search state.
- Nonempty Search with body focus producing the localized default title.

The negative control substitutes the submitted query at the title-creation boundary in the disposable process.
That plausible wrong implementation fails the literal-title assertion (`negative-control.log`, expected exit 1).
It still passes menu dispatch and distinct-note creation first, so the failure isolates the title oracle.

Commands, from the repository root:

```sh
python3 Tests/ViewControlsReview/run-probe.py --probe Tests/FocusedSearchNewNoteReview/round1/contrarian/probe.inc
NV_CONTRARIAN_STALE_TITLE=1 python3 Tests/ViewControlsReview/run-probe.py --probe Tests/FocusedSearchNewNoteReview/round1/contrarian/probe.inc
```

Reviewed executable SHA-256: `ffd2506757bfb23cfc26450ce1a736a578babd22af606a313427a6db7e399c43`.

## Limits and fixture corrections

The first sandboxed launch exited without application output; the desktop launch required normal desktop access.
The first desktop probe compared an attributed body directly with an NSString. That fixture error was corrected to compare its string.
The final production run and mutation run use the corrected probe committed here.

The probe uses Exact mode to hold the submitted-query state deterministic; it does not add asynchronous or input-method coverage.
It synthesizes the menu key equivalent rather than a hardware key event.
It does not test file-format persistence or rerun the broad desktop suites.
No production source changed during this review.
