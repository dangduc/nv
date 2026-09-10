# Round 2 — Dan Luu review

## Result

No actionable findings.

The round-one fixes close the manual-completion gap and make the decoded source
editors match the `NSTextView` defaults observed in the same process. I also
tested retired preferences at application startup rather than only mutating them
after the editor had loaded.

## Executable evidence

Run:

```sh
python3 Tests/NativeEditingReview/round2/luu/run.py
```

The isolated Intel application probe passed 39 runtime checks. It supplied all
six retired preference keys as launch arguments, then compared the decoded
source editor with a freshly allocated plain `NSTextView`. Continuous spelling,
spelling correction, Smart Copy/Paste, Smart Quotes, Smart Dashes, text
replacement, and writing direction matched. Each surviving Text-menu toggle
routed through the first-responder chain, changed the active editor, and restored
its initial state.

The probe also compared source-editor and plain-`NSTextView` results for seven
consecutive Backspaces in the reported whitespace fixture; Backspace beside four
spaces, a surrogate-pair emoji, a combining sequence, a family emoji sequence,
and indentation; Tab insertion; and RTF paste into a plain editor. Strings,
selections, and pasted presentation attributes matched the native reference.

The structural portion checks all six localizations. It parses each active XIB,
checks native menu action wiring and source-editor Smart Copy/Paste state, checks
both Format menus for leading separator residue, decodes every shipped help RTF
with `textutil`, and verifies that retired selectors and preference tokens are
absent from production source.

For completion, the runtime probe verifies that `LinkingEditor` inherits
`complete:` from `NSTextView` and that its actual browser delegate no longer
implements the note-title completion callback. This directly closes the round-one
finding.

## Validation limits

The completion panel is not automated because `complete:` enters an interactive
AppKit UI path in the injected harness. The evidence establishes implementation
identity and absence of nv's provider, rather than driving the panel with a
physical keyboard. Backspace and Tab use their command selectors rather than
hardware key events. The localization audit parses XIB XML; the branch's full
application build provides the Interface Builder compilation check.

No production code changed during this review.
