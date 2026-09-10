# Round 1 contrarian review: native editing boundaries

## Finding

### P3 — Source editors still decode with non-native Smart Copy/Paste behavior

The source editor does not start with the same Smart Insert/Delete value as a fresh, plain `NSTextView` in the same process. The injected app probe recorded:

```text
REVIEW OBSERVATION: smart insert/delete editor=0 native=1
CONTRARIAN FINDING: decoded source editor does not use native smart insert/delete default
```

This is actionable because the change states that Cocoa owns editor-local behavior and replaces the old global Smart Copy/Paste binding with `toggleSmartInsertDelete:`. The menu command now works, but a newly decoded source editor starts disabled while the native reference starts enabled. The twelve localized editor instances in `MainMenu.xib` and `BrowserWindow.xib` omit `smartInsertDelete="YES"`; old Interface Builder archives decode that omission as false even though a fresh `NSTextView` defaults to true.

Set `smartInsertDelete="YES"` on each localized `LinkingEditor` node. This preserves the native default without adding another production-code override. Add the value to the source-editing regression so future XIB edits cannot silently change it.

## Evidence

Run:

```sh
python3 Tests/NativeEditingReview/round1/contrarian-b/run.py
```

The executable intentionally exits 2 while the mismatch is present. Before reporting it, the probe completed 28 runtime checks:

- keyboard, pasteboard, drag, and Services methods use the `NSTextView` implementations;
- spelling, automatic spelling correction, quotes, dashes, and text replacement match a fresh plain `NSTextView`;
- retired nvALT defaults do not change live editor-local features;
- all five native Edit-menu toggles resolve to the active source editor;
- rich paste inserts the same characters as a plain `NSTextView` and does not retain foreign font or foreground color;
- native copying writes only the selected source characters.

The static half parsed and compiled all 12 changed localized Preferences/MainMenu XIBs, checked all six BrowserWindow editor nodes, verified native menu actions, and rejected removed preference/action symbols in production sources.

## Validation limits

The drag boundary is verified through implementation identity, not a synthesized mouse drag. Paste and menu behavior run in an isolated copied app. The probe does not exercise IME composition, Accessibility input, or Services supplied by another process.
