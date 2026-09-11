# Round 1: selection anchors and paragraph history

No actionable finding. The new review passed 182 checks at frozen commit `9e6c8dd6adc058e7044f2c562532af97dd4e63d4`, against base `75d6f42`.
The earlier 32-check implementation suite is separate and does not count toward this review.
This review uses a Kyle Kingsbury-inspired focus on consistency and history. It does not represent Kyle Kingsbury.

## Executed evidence

Command: `python3 Tests/WrappedSeparatorReview/round1/kingsbury/run.py`.

The first copied-app process passed 168 checks.
It joined and split a real paragraph twice while another window held a selected phrase.
Each join replaced a newline and indentation with one separator. Each split restored the newline and indentation.
The history changed fonts between Menlo 18 and Helvetica 19 and changed both window widths.
Undo and Redo restored the expected source while the peer selection remained attached to the same phrase.

The second copied-app process passed 14 checks after reopening the saved disposable library.
The note UUID, complete UTF-8 source, and copied phrase matched the saved expectations.
The same font and window size reproduced the complete saved native glyph geometry.

All 33 comparisons matched fresh production layouts.
Each comparison checked character ranges, glyph ranges, line rectangles, used rectangles, glyph positions, and any extra line fragment.
Line ranges covered every source character exactly once. Both paragraph-cache pointers were empty after completed layout.
Layout preserved source attributes and logical selections.

## Test boundary

The runner injects new histories into a copied actual app.
The checks use real browser controllers, shared editing sessions, source editors, native editing commands, Undo, Redo, copy, library flush, and library startup.
The runner uses disposable notes, isolated preferences and support files, a private pasteboard, and the shared GUI lock.
It released that lock after both processes exited.

The fresh comparison uses a new instance of the linked production typesetter with matching source attributes and text-container settings.
The actual editor supplies its production glyph delegate. The comparison contains no alternative separator algorithm.
The startup and comparison infrastructure comes from earlier word-wrap review tests. The paragraph, selection, and font histories are new.

The fixture reapplies the saved logical selection after reopening before the copy comparison.
This checks saved source offsets and bytes, not automatic window-selection restoration.
The font changes exercise native source attributes. They do not cover arbitrary rich-text paragraph styles.

## Results and limits

- App SHA-256: `f1918d1d728fe257fe76368cebaadee2625ac3bc8688ab7c3b3cef977ec22384`.
- macOS 26.5.2, Xcode 26.6, Intel app through Rosetta.
- Both app processes exited with status 0.
- Production hashes stayed unchanged and match the frozen commit.
- `results.json` records the environment, hashes, phase results, and assertion counts.
- `save-observations.json` and `reopen-observations.json` record the layout comparisons.
- `save.log` and `reopen.log` record the assertions. `expected.json` contains the disposable expectations.

Fresh-layout equality detects stale layout after history changes. It cannot expose a deterministic error shared by both compared layouts.
This review does not cover interrupted writes, physical IME input, compositor pixels, or macOS 13.7.8.
The successful save/reopen check does not require Undo history to persist across app processes.
No production or earlier test files changed.
