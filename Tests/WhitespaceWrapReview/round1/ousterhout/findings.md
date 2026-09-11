# Round 1: Ousterhout perspective

No actionable finding within this review's ownership and abstraction scope.
This review uses engineering priorities inspired by John Ousterhout. It does not represent his authorship or endorsement.

The reviewed change is commit `83a7307`, against base `f772c4b`.
The production method is in `Sources/Editor/LinkingEditor.m`, lines 286–312.
The existing editor delegate owns the new display adjustment. It introduces no shared ownership or persistent state.

## Executed evidence

`run.py` injects a new probe into a copied Development app.
The probe calls the real `LinkingEditor` and native layout managers. It does not replace or reproduce the production method.
The runner holds `build/pr-review/gui.lock` and uses disposable notes, preferences, and support paths.

The candidate passed 162 functional checks, plus one optional PNG capture check.
The app binary SHA-256 was `6682e85cff4069c18b65ef9989830de2b72c3513240302a197395551d53d7d0c`.
The host was macOS 26.5.2 (25F84), with the Intel app under Rosetta.

The checks cover two native browser editors over 901 ordinary source spaces:

- Twelve paired resize and glyph-regeneration cycles preserved source characters and all source attributes.
- Layout produced zero text-storage edit notifications and zero new Undo or Redo actions.
- Both editors retained their independent selections and temporary display attributes.
- The existing layout-completion callback still ran after glyph regeneration.
- Five note switches detached only one layout manager and preserved the peer's source and selection.
- Reattachment reused the original shared storage and retained both editor delegates.

The same probe failed on the baseline app at `actual production delegate wraps the source spaces`.
That failure occurred after five setup checks passed. It is the negative control for the changed display behavior.
The baseline binary SHA-256 was `d2fc91aab87fbb3937073e11908832d177559761e46237ecd597a3bd9ca5ec80`.
The initial sandboxed app run stopped before probe output. The desktop run then completed as described here.

## Limits and visual observation

This probe does not measure key-repeat frame timing, every font, or macOS 13 behavior.
It checks display-only ownership and state preservation during explicit layout operations.
The checks do not establish performance bounds or all word-break semantics.

The optional screenshot contains this exact source at Menlo 18 in a 560-point window:

```text
Ordinary spaces wrap naturally.\n\nStart →[151 U+0020 spaces]← End\n\nSource text is unchanged.
```

The bracketed text describes the actual run of 151 ordinary spaces.
In the screenshot, `Start` occupies one line, and the following arrow starts the next visual line.
The space run then advances the end marker through subsequent lines.
The `Start →` prefix alone fits within the line width.
This is a word-break observation, not a confirmed finding about the intended new space semantics.
The baseline negative control stops before this fixture, so this review has no baseline geometry for that observation.
The independent UX review can determine whether this change needs a different break policy.

## Reproduce

From the worktree, run:

```sh
python3 Tests/WhitespaceWrapReview/round1/ousterhout/run.py --capture
python3 Tests/WhitespaceWrapReview/round1/ousterhout/run.py --label baseline \
  --app /Users/duc/dev/nv/build/TypingPerformanceWorktree/build/DerivedData/Build/Products/Development/nvALT.app
```

The second command is expected to exit with status 1 at the wrapping assertion.
Generated logs, result records, and the screenshot are in `build/WhitespaceWrapReview/round1/ousterhout/`.
The committed `results.json` contains the small result records from both runs.
