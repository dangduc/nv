# Round 2: Contrarian UX perspective

No actionable finding.
The frozen revision is `072a6bc0f54a52603f8cedfbcacc17d0ab836a36`.
This review challenges native caret movement and selection around the new visual wrap boundaries.
Character wrapping is the selected source policy. Visual breaks within words are intentional.

## Executed evidence

The new probe passed 2,881 checks in the actual copied app.
It sends native `NSApp` keyboard events and calls native insertion hit tests.
It does not replace the editor's key handling, caret drawing, or glyph methods.
The runner uses the shared GUI lock, disposable notes, and isolated preferences.

The fixture contains `alpha beta`, 151 ordinary spaces, `tail`, a hard newline, and `last line`.
The font-and-width cases are Menlo 12/480, Menlo 22/480, Menlo 18/560, and Helvetica 14/480.
Widths are window-content points. The resulting layouts contain four, six, five, and three visual lines.

- All 1,400 native Left and Right events visit exactly one source character per event.
- The sampled caret coordinates move monotonically along the source and remain within the editor's horizontal bounds.
- Thirty native insertion hit tests round-trip space positions at the beginning and end of visual lines.
- Twenty-four Shift-arrow events extend and contract selections across wrap boundaries with the expected source ranges.
- Command-Left and Command-Right reach the expected visual line boundaries.
- Native Home and End preserve the selection in these fixtures.
- Every fixture retains its exact source and committed note content after all navigation operations.

The probe sends 1,440 keyboard events in total.
The extra events cover Shift selection, Command-Left/Right, Home, and End.
It forces layout through insertion-rectangle queries after every ordinary arrow event.

Host: macOS 26.5.2 (25F84), Intel app under Rosetta.
The executable SHA-256 is `be02dd1fe33a39c74b8961441be55f4f91378d46935bdba99fd610d405c3e09b`.

## Reproduce

From the worktree, run:

```sh
python3 Tests/WhitespaceWrapReview/round2/contrarian_ux/run.py
```

The runner reuses the established copied-app launcher and native geometry helpers.
The keyboard sequence, wrap-edge hit tests, and selection checks are new for this round.
The committed `results.json` contains the binary identity and compact navigation records.
Generated logs remain in `build/WhitespaceWrapReview/round2/contrarian_ux/`.

The first probe expected Command-Right to move past a hard newline.
The final probe expects the insertion position before that newline and passes all cases.
This correction changes the test expectation, not production behavior.

## Limits

Layout queries force completion before the geometry checks. They do not measure every painted frame or physical key-repeat timing.
The hit tests exercise native pointer-to-index mapping. They do not reproduce full mouse-down, drag, and mouse-up tracking.
The monotonic movement checks use left-to-right text. This review does not establish bidirectional or input-method behavior.
The current host does not establish macOS 13 behavior.
