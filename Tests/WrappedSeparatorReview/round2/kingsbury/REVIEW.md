# PR30 Round 2: seeded editing history

No actionable issue was found in this bounded history. This review uses a Kingsbury-inspired consistency lens; it does not represent his review.

The copied production app passed 117 assertions at frozen commit `2ea92180939a3e51df8fe867ad548140ed455868`.
The runner verified the four editor source files against that commit and confirmed unchanged hashes after execution.
The app executable SHA256 was `f1918d1d728fe257fe76368cebaadee2625ac3bc8688ab7c3b3cef977ec22384`.

## Hypothesis and evidence

Repeated separator changes could leave one shared editor with stale layout or make Undo restore the wrong source.
The test creates one disposable note and two actual browser windows with different widths.
The windows share text storage and use separate production typesetters.

Seed 2 selects twelve transitions among three independently constructed source strings:

- Forty-eight `x` characters followed by ` tailword`.
- The same prefix followed by `  tailword`.
- The same prefix followed by one trailing space.

The recurrence is `seed = 1664525 * seed + 1013904223` with unsigned 32-bit arithmetic.
The next state is `(state + 1 + ((seed >> 16) & 1)) % 3`.
The resulting history covers all six directed transitions and alternates the originating editor.
Each edit uses native `insertText:replacementRange:` or `deleteBackward:` and is followed by native Undo and Redo.
This produces exactly 36 edit/history commands.

After the baseline and every command, the test checks these invariants:

- Both editors and the note model exactly equal the independent expected string.
- Both existing layouts equal separately created production layouts, including glyph positions and line rectangles.
- Line character ranges are contiguous and cover the complete source exactly once.

All 37 observations passed, including 74 fresh layout comparisons. The disposable library also flushed successfully.
The JSON record stores expected strings and line ranges for each observation.

## Reproduction and limits

Run from the worktree in an active desktop session:

```sh
python3 Tests/WrappedSeparatorReview/round2/kingsbury/run.py
```

Use `--compile-only` to compile without launching the app.
The runner copies the app, uses disposable notes and preferences, and holds the shared GUI lock during execution.
The lock was released after this run.
Execution used macOS 26.5.2, Xcode 26.6, and the Intel app through Rosetta.

This is an actual app test using native editor methods, without physical keyboard events.
It covers one seed, Menlo 18, two fixed window widths, and three ASCII source states.
Fresh layout equality detects stale results; it cannot detect an error shared by both fresh and existing production layouts.
This round does not test selection anchors, pasteboards, reopen, composition, or other operating system versions.
