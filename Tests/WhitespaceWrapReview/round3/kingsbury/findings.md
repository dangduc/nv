# Round 3: state history review

This review uses a Kyle Kingsbury-inspired perspective. It does not represent Kyle Kingsbury or his endorsement.

No actionable findings. Closing a browser during marked-text composition preserved source, model, and Undo history in all eight cases.
The final build matched the previous build across all 84 recorded states, including each surviving editor's selection.

The reviewed head is `4b725372670afd5f5ecadf512deba8498336b2f0`.
The candidate executable SHA256 is `55f97d1af69d120f385698b428a616e473be020200d3fe0ebcc6b626253459be`.
The control executable SHA256 is `be02dd1fe33a39c74b8961441be55f4f91378d46935bdba99fd610d405c3e09b`.
Both builds use character wrapping and the shared paragraph style. The control predates the glyph-buffer optimization.
The runner's `baseline` result refers to this control, not the original native word-wrapping build.

## New evidence

Run `python3 Tests/WhitespaceWrapReview/round3/kingsbury/run.py` from the worktree.
The runner copies both actual apps, installs an observer around the production glyph delegate, and uses disposable notes and preferences.
It holds the shared GUI lock during both runs.
The test ran on macOS 26.5.2 (25F84), using the Intel Development apps under Rosetta.

The seed contains a header and `alpha beta`, followed by thirteen spaces and `END`.
An additional browser replaces `END` with native marked text while the original browser remains open.
Each marked candidate contains 63, 64, 65, or 257 spaces, followed by a combining accent and a joined emoji cluster.
Half the cases also apply a nonoverlapping external prefix through the note model while composition remains active.

Each history then closes the composition owner while it still has marked text.
The surviving peer inserts a character, undoes that insertion and the closed composition, then redoes both operations.
A new browser reopens the same note, deletes the final ASCII character, and the original peer undoes that deletion.

Both builds passed 874 checks. Each run observed:

| Evidence | Count |
| --- | ---: |
| Recorded source/model/selection states | 84 |
| Production glyph delegate calls | 481 |
| Delegate calls during marked text | 56 |
| Changed batches at most 64 glyphs | 52 |
| Changed batches above 64 glyphs | 177 |
| Lines in the 201-space geometry control | 5 |

The results JSON records 873 checks because the final successful evidence-write check occurs after serialization.
The application logs include that last check and report 874.

The assertions verify exact source and committed model contents, shared storage identity, bounded selections, and composition state.
Closing the owner detaches exactly its layout manager. Reopening attaches one new layout manager to the existing shared session.
Explicit glyph regeneration preserves full source attributes, source generation, model contents, selections, marked ranges, and Undo/Redo availability.
Pending external prefixes survive owner closure and remain present when the local composition is undone.

## Limits

Composition uses native `setMarkedText:` APIs. This does not test a physical input method, candidate panel, or operating-system composition cancellation.
External changes enter through the real note model setter, without filesystem watcher timing or overlapping merge conflicts.
The test closes an additional browser while a peer remains alive. It does not test closing the last browser or quitting during composition.
Unicode clusters remain within the composition; the later Backspace removes an ASCII character.
The bounded histories exercise both buffer sizes but do not measure frame latency or establish behavior on macOS 13.
