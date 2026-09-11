# Round 3: Ousterhout perspective

No actionable finding.
This review uses engineering priorities inspired by John Ousterhout. It does not represent his authorship or endorsement.

Frozen revision: `4b725372670afd5f5ecadf512deba8498336b2f0`.
The review targets buffer lifetime and editor ownership in `LinkingEditor.m:286–324`.
It also checks the shared immutable paragraph policy from `GlobalPrefs.m`.
Character wrapping, including breaks within words, is the selected behavior.

## Executed evidence

The new copied-app probe passed 117 checks.
It forwards the actual production glyph callback unchanged and records its returned batch sizes.
Those observations confirm 146 changed batches with at most 64 glyphs and 38 changed batches above that threshold.
Another 44 callbacks returned zero and used native handling.
These cases exercise both optimized buffer paths and the native return path.

Three peer windows were created and closed in sequence.
Each lifetime included three paired-note attachment cycles over short, long-space, and mixed-script notes.
The fixtures use 19, 618, and 35 UTF-16 units respectively.
The long fixture includes 601 consecutive ordinary spaces.
Font changes use Menlo 12, Menlo 22, and Helvetica 16.
Each cycle also refreshes text colors and assigns different window widths.

The checks establish these results:

- Each editor retains its own layout manager and delegate while sharing the selected note's storage.
- After another layout uses the callback, the first layout retains identical glyph IDs, properties, and character indexes.
- Regenerating that first layout produces the same glyph arrays.
- Glyph generation preserves source attributes, selections, source generation, modified dates, and Undo/Redo availability.
- Switching the peer to another note cannot change the first note's source or wrapper attributes.
- Reattachment reuses the original storage and immutable paragraph policy.
- Closing each peer preserves the surviving editor's storage and working glyph callback.

The glyph-array comparison runs after the production callback returns.
This supplies direct evidence that AppKit retains its own glyph values rather than depending on the expired local array.
It does not prove all possible allocator or object-lifetime paths.

The runner reuses the established copied-app launcher and adds new callback-observation and lifecycle cases.
It uses disposable notes, a unique preference domain, and the shared GUI lock.
No user notes or shared clipboard are accessed.

## Reproduce

```sh
python3 Tests/WhitespaceWrapReview/round3/ousterhout/run.py
```

Host: macOS 26.5.2 (25F84), Intel app under Rosetta.
Executable SHA-256: `55f97d1af69d120f385698b428a616e473be020200d3fe0ebcc6b626253459be`.
`results.json` records the executable, check count, and observed batch counts.
The full generated log is in `build/WhitespaceWrapReview/round3/ousterhout/candidate.log`.

## Limits and test corrections

The initial assertion spanned a pending preference refresh.
A later note attachment applied the requested font and foreground color through the existing session refresh path.
The final probe first reattaches the note and verifies the requested font before taking the layout-only attribute snapshot.
It then checks that unrelated buffer operations leave that snapshot unchanged.
The paragraph policy and source characters remained intact during the initial run as well.

This bounded probe does not measure allocations, painted frame timing, or arbitrary heap reuse.
It does not test input-method composition, process shutdown, or macOS 13.
It observes Undo/Redo availability during layout; the prior round covers actual snapshot Undo and Redo.
