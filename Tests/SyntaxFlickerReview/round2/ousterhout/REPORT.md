# Round 2: editing-session ownership

This review uses a John Ousterhout-inspired design perspective. John Ousterhout did not participate or endorse the review.

No actionable introduced defect was found in PR #6, production revision `65e1608`, against base `8cd2c95`.
The native probe completed **36 checks**, including four startup and activation checks. It exited with status 0.

The review asks whether display state remains inside the source-analysis boundary when real browser sessions change content and ownership.
The changed code separates provisional display eligibility from current syntax analysis. It does not alter model commits or Undo registration.
The probe checks those boundaries through three histories in two actual browser windows:

- Native marked text changes shared live source while the model and Undo remain unchanged. A disjoint external body update is then deferred. Parsing completes during composition without committing it or replacing the external model. Undo from the other browser finishes composition and preserves external text. Redo restores the exact merged body in both windows.
- An ordinary edit starts a provisional revision. One browser switches immediately to a plain note before the parser debounce completes. Its foreground returns to the browser's base color. The remaining peer receives fresh captures for the original note. After both layouts detach, returning starts fresh analysis. Undo and Redo still remove and restore exactly the earlier insertion.
- Library deletion and deletion Undo restore the exact note body and local syntax. Fresh analysis completes on the restored note. Body Undo retains the earlier edit boundary. The previously selected plain note retains its exact body and empty Undo history.

The test also checks that syntax capture attributes never enter either committed note model. No extra notes are created.
Display assertions use the real `LinkingEditor` drawing delegate and actual TextKit layout managers. They compare syntax and base foreground colors.

The initial fixture required three corrections. Their logs remain in this directory:

- `initial-fixture-output.txt`: inserting `draft ` before `#` removed the only Markdown heading. The parser correctly produced no captures, so current-capture waiting was invalid. The final fixture inserts after `# ` and preserves the heading.
- `initial-default-color-output.txt`: plain source returns the browser's base foreground color, rather than a nil foreground. The final assertions compare that actual base color.
- `initial-deletion-output.txt` and `deletion-routing-output.txt`: library Undo reveals the restored note in the active browser. The diagnostic confirmed both browsers then displayed the restored note with the correct body. The final assertions check this selected-note identity and verify that the unselected plain model remains unchanged.

These failures were fixture assumptions, not confirmed production defects. No production changes were made.

Reproduce from the repository root:

```sh
python3 Tests/ViewControlsReview/run-probe.py \
  --probe Tests/SyntaxFlickerReview/round2/ousterhout/checks.inc \
  --prefix Tests/SyntaxFlickerReview/round2/ousterhout/prefix.h \
  --app build/SyntaxFlickerReview/fix.app
```

The runner uses a copied app, a unique preferences domain, disposable notes, and the shared GUI lock.
Evidence: [native probe](checks.inc), [drawing helpers](prefix.h), [passing output](output.txt).
Host: macOS 26.5.2 (25F84), Xcode 26.6 (17F113), Intel app under Rosetta.

Limits: this probe covers Markdown and plain source, one disjoint external update, and native `setMarkedText:` calls.
It does not simulate a physical input method, overlapping merge conflicts, arbitrary parser completion orders, disk recovery, or process restart.
The external snapshot enters through `NoteObject setContentString:`, rather than a live sync service or filesystem watcher.
The test checks immediate and eventual display attributes. It does not measure rendered frame timing.
