# Round 2: metadata and presentation boundaries

Review perspective: John Ousterhout-inspired abstraction analysis. This report does not claim his authorship.

Reviewed application commit `504f30353275663d5174656b03805625275e603a`, all five round 1 reports, and their executable probes.
The later `efa6e0a` commit adds review evidence only.

No actionable findings.

The round 1 evidence supports its reported title, ownership, and stale-callback conclusions within the stated limits.
This round tests different transitions: pending metadata commits and Preview with visible or hidden header fields.

`newNote:` determines the title before `finishEditing` commits old metadata (`Sources/Browser/AppController_BrowserUI.m:319`).
Search focus remains distinct from the shared field editor used by title and tag controls.
The explicit title parameter adds no dependency on the selected note's metadata or viewer state.
The existing metadata commit path continues to target the old note (`Sources/Browser/AppController_BrowserUI.m:263`).

## Executed evidence

```sh
python3 Tests/ViewControlsReview/run-probe.py \
  --probe Tests/FocusedSearchNewNoteReview/round2/ousterhout/probe.inc
```

Result: exit 0; **27 checks passed**, including three setup checks. Full output is in `output.txt`.

Four cases dispatch Command-N through the real application menu in a copied app with disposable notes:

- A pending title edit commits to the original note; the new note receives the default title.
- A pending tag edit commits to the original note; its tags do not move to the new note.
- Preview has focus while Search contains text; the new note receives the default title.
- Search has focus while Preview is displayed; the new note receives the search title.

The metadata cases use visible headers. The Preview cases hide the title and tag headers.
Every case verifies one new note, empty source, Source mode, and the configured initial editing focus.
The Preview cases also verify preservation of the original title, tags, and source.
This round does not swap production methods or inject synthetic callback behavior.

## Limits

The probe checks Preview mode and its focus boundary. It does not wait for completed HTML rendering or inspect rendered pixels.
Keyboard delivery uses the application menu's key-equivalent API, not a hardware keyboard.
This single-window probe does not repeat round 1 persistence, input-method, or callback-schedule checks.
It does not establish that the broad desktop suites pass.

Tested executable SHA-256: `ffd2506757bfb23cfc26450ce1a736a578babd22af606a313427a6db7e399c43`.
Environment: macOS 26.5.2 (25F84), Xcode 26.6 (17F113), Intel app through Rosetta.
No production files changed during this review.
