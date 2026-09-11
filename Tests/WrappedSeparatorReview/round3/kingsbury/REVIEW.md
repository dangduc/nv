# PR30 Round 3: Unicode neighbor history

No actionable issue was found in this bounded actual-app history.
This review uses a Kingsbury-inspired consistency lens; it does not represent his review.

The copied production app passed 150 assertions at frozen commit `e022109eaf2bad6583512c2ed2b48561d9dae011`.
The runner verified editor source hashes against the frozen commit and confirmed unchanged hashes after execution.
It also required the rebuilt executable SHA256: `b28da33e5f645a589f4802d778225693f7e0764abf6a48a21690d154421ad40c`.

## History and invariants

The hypothesis was that neighbor changes could leave stale separator glyph properties or layout in a shared editor.
Ten native replacements alternate between two browser windows with different widths.
Each replacement is followed by native Undo and Redo, for 30 edit/history commands.
The source starts with 48 `x` characters followed by ` tailword`.

The history replaces neighbors with an accented character, a CJK character, and combining sequences, then restores ASCII after each case.
It also attaches U+0301 directly to the space and removes it again.
These states exercise the ASCII shortcut and Unicode fallback, including a space that belongs to a longer composed character.

The probe uses literal reference strings and explicit UTF-16 replacement ranges.
After each command it checks:

- Both editors and the note model exactly match the expected UTF-8 source.
- Both existing layouts equal fresh layouts using the actual production typesetter and glyph delegate.
- Line character ranges cover the source contiguously, without gaps or overlap.
- Both separator glyphs retain the elastic flag expected from the composed-character policy.

Both editors switch to another disposable note and return while the space has an attached combining mark.
They repeat that cycle after restoring ASCII.
Intermediate checks confirm that switching one editor does not replace its peer's source.
Reattachment restores shared storage and matching fresh geometry.

All 35 observations passed, including 70 fresh geometry comparisons. The disposable library also flushed successfully.
The compact JSON record stores exact expected strings and line ranges.

## Reproduction and limits

Run from the worktree in an active desktop session:

```sh
python3 Tests/WrappedSeparatorReview/round3/kingsbury/run.py
```

Use `--compile-only` to compile without launching the app.
The runner copies the app, uses disposable notes and preferences, and holds the shared GUI lock during execution.
The lock was released after the run.
Execution used macOS 26.5.2, Xcode 26.6, and the Intel app through Rosetta.

The initial probe used NSString substring search to locate the separator.
That search did not match a bare space inside the combining sequence and caused a probe exception.
Explicit UTF-16 scanning corrected the lookup. The complete rerun passed without production changes.

This evidence covers one font, two fixed widths, and the stated ten transitions through native editor methods.
It does not cover physical key events, IME composition, process reopen, or other operating system versions.
Fresh geometry equality detects stale results but cannot detect an error shared by fresh and existing production layouts.
