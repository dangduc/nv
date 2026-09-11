# Round 2 cache lifetime and edit cost

The runner links frozen production implementations from commits `4b049709b2cecc6eac80514586ccacc119d12802` and `4c8f6b449504a50caa460d78efebd42b94beaba6`.
It renames the previous class so both implementations run in the same process.
Both modes use the current production space glyph delegate and character paragraph style.

Run these commands from the worktree:

```sh
python3 Tests/WordWrapReview/round2/luu/run.py --instrument
python3 Tests/WordWrapReview/round2/luu/run.py
```

The call-count run wraps actual production Core Text creation and release calls.
It tracks measurement snapshot lengths and inspects the production cache fields after completed operations.
The run covers cached viewport queries, empty-storage attachment, reattachment, progressive viewports, edits, and twelve simultaneously alive text systems.
Its 16,000-character fixture repeats `one two three four five six seven eight nine ten. `.
The progressive viewport fixture contains short paragraphs in a 4,000-character document.

The timing run has no call wrappers. Each mode receives one warmup and seven measured trials, in alternating order.
Each trial starts with a 100-character note. It inserts 96 letters, then removes them, with native layout after each operation.
Source setup and exact source postchecks occur outside the timed interval.
The interval includes text-storage mutation and layout of a 544-by-200-point viewport.

Both runs use Menlo 18 in main-thread Cocoa text systems, without windows, application preferences, or a note library.
The binaries use x86_64, `-O1`, and the macOS 10.13 deployment target.
Generated source, binaries, and logs stay under `build/WordWrapReview/round2/luu`.
The committed JSON files contain the recorded results.
