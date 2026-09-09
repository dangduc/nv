# Round 2 — Kyle Kingsbury correctness perspective

This review uses a Kingsbury-inspired perspective. It does not claim his authorship or endorsement.

No actionable defect was attributed to this PR. A separate direct-`unmarkText` exception is recorded below with a control and its limits.

I read all five Round 1 reports. This round tests composition and persistence boundaries, rather than repeating the delayed-callback schedules.
The corrected production revision is `0fc7aca`: `3297f6e` plus the macOS appearance API guard and scoped fallback.
The app SHA-256 is `0e877e5a1576b932b6bedfb85770a918f266925f0cc844120cce0987a889f695`.
The host runs macOS 26.5.2 (25F84), Xcode 26.6 (17F113), with the Intel app under Rosetta.

## Passing evidence

```sh
python3 Tests/ViewControlsReview/run-probe.py \
  --app build/UserSchemeReview/compatibility-fixed/nvALT.app \
  --probe Tests/UserSchemeReview/round2/kingsbury/probe.inc \
  --prefix Tests/UserSchemeReview/round2/kingsbury/prefix.h \
  --launches 2
```

Result: exit 0, **86 checks passed**: 62 in the first process and 24 after restart, including setup checks.
See [probe.inc](probe.inc), [prefix.h](prefix.h), and [output.txt](output.txt).

The probe creates Markdown and JSON notes. Two windows initially share the Markdown source and an actual Exact-search decoration.
The key editor starts native marked-text composition with Japanese text and an emoji. Six application appearance changes follow.
During that sequence, the dark background, dark highlight, and light foreground change. The peer also navigates to the JSON note.

The assertions establish these results:

- Both windows inherit the application appearance and resolve the corresponding palette.
- Marked range, selection, focus, complete attributed live source, and source generation remain unchanged during presentation changes.
- The model retains its previously committed source until composition ends. Neither note gains an Undo action during the presentation changes.
- Actual asynchronous search processing installs no stale committed-source background into the uncommitted composition.
- Peer navigation detaches its editor from the composing note without committing that note or changing the peer's source.
- Native `insertText:replacementRange:` ends the composition and commits the full text. Only the composing note gains an Undo action.
- Both notes retain UUID, title, committed source, syntax identifier, and tags after successful checkpoints and process restart.
- Five explicitly edited preference archives survive byte for byte. The untouched dark foreground remains a registration-only default across restart.

The restarted app opens each note and draws both palettes without changing its source.

## Direct-unmark observation and control

An earlier variant ended composition by calling `unmarkText` directly. It passed all presentation-state assertions, then raised:

```text
NSBigMutableString characterAtIndex: Index 43 out of bounds; string length 37
```

The stack passes through `NSTextView unmarkText`, `NSTextStorage processEditing`, and `NSLayoutManager removeTemporaryAttribute:forCharacterRange:`.
The retained output is [unmark-transitions.txt](unmark-transitions.txt). Run that variant with `NV_SCHEME_USE_UNMARK=1`.

A bounded control disables all six appearance changes and all three in-composition palette edits. It reproduces the same exception.
It keeps the same peer navigation and calls the same direct unmark operation. See [unmark-control.txt](unmark-control.txt).

```sh
NV_SCHEME_NO_TRANSITIONS=1 NV_SCHEME_USE_UNMARK=1 \
  python3 Tests/ViewControlsReview/run-probe.py \
    --app build/UserSchemeReview/compatibility-fixed/nvALT.app \
    --probe Tests/UserSchemeReview/round2/kingsbury/probe.inc \
    --prefix Tests/UserSchemeReview/round2/kingsbury/prefix.h
```

Both unmark variants exit 1 before the commit and restart oracles. They do not establish successful persistence.
The passing run uses the native input-client commit operation. It does not suppress callbacks or modify production behavior.

The control establishes that the exception does not require the palette or appearance transitions in this schedule.
It runs the current binary; it is not a prior-revision baseline build. It therefore does not prove when the exception was introduced.
No production change is proposed without evidence that this PR causes it.

## Limits

The input uses public NSTextInputClient operations, not a physical input-method candidate panel. Appearance changes use the native application API, not the user's system preference.
The probe inspects Undo availability and absence of new actions during presentation changes. It does not execute body Undo or Redo.
Persistence follows successful library flushes and `NSUserDefaults synchronize`. It does not establish crash durability, power-loss behavior, or an atomic transaction across notes and preferences.
The probe runs on this host and does not test the pre-macOS-11 fallback. That path is covered by the separate compatibility review.
