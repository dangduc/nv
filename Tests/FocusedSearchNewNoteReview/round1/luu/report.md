# Round 1: Dan Luu-inspired review

This review uses a Dan Luu-inspired focus on observed UI behavior and boundary conditions. It does not represent his authorship.

Reviewed application commit: `504f30353275663d5174656b03805625275e603a` against upstream `b289ba3`.

## Findings

No actionable findings.

The title snapshot at `Sources/Browser/AppController_BrowserUI.m:319` preserves the complete live field-editor string. It survives both partial selection and clearing the search field. It does not use only selected or marked text.

## Executed evidence

```sh
python3 Tests/ViewControlsReview/run-probe.py \
  --probe Tests/FocusedSearchNewNoteReview/round1/luu/checks.inc \
  > Tests/FocusedSearchNewNoteReview/round1/luu/output.txt 2>&1
```

Result: **53 checks passed** in the copied app with disposable notes. The shared runner serializes desktop access with `build/pr-review/gui.lock`.

Seven supplementary cases dispatched Command-N through the application menu:

- Decomposed accented characters.
- Joined emoji and emoji with skin-tone modifiers.
- Mixed Hebrew, Arabic, and English.
- Leading and trailing spaces.
- A title containing only spaces.
- A title with 8,192 UTF-16 code units.
- A marked Japanese replacement surrounded by unmarked text.

The first six cases use native `insertText:replacementRange:` with attributed input and select only part of the resulting text. They alternate Exact and Fuzzy modes. Each case verifies byte-for-byte UTF-8 title equality, exactly one created note, cleared search text, and a successful subsequent search. The composition case also verifies that the marked range does not discard its prefix or suffix.

Single-call timings are recorded as observations. The large-title command took 26.906 ms on this host. These timings include synchronous note creation and are not a latency benchmark or a claim about large libraries.

## Environment and limits

- macOS 26.5.2 (25F84), Xcode 26.6 (17F113), Intel app through Rosetta.
- Tested executable SHA-256: `ffd2506757bfb23cfc26450ce1a736a578babd22af606a313427a6db7e399c43`.
- The first compile attempt caught a bracket typo in this probe. The corrected probe compiled and ran successfully.
- A sandboxed app launch exited before producing output. The reported result comes from the desktop-enabled run.
- IME coverage uses AppKit's marked-text API. It does not exercise every system input method or candidate panel.
- This probe does not repeat the implementation's 101-check suite or claim that the broader desktop suites pass.
- No production code changed during this review.
