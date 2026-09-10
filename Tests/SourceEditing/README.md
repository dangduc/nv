# Native source editing regression

`run.py` launches a copied Development app with an isolated library. It checks
that the source editor delegates ordinary editing commands to `NSTextView`.

Build the Intel Development app, then run:

```sh
python3 Tests/SourceEditing/run.py
```

The native probe covers Return, Backspace, Tab, character pairs, word
selection, the absence of source title completion, spelling, writing direction,
Smart Copy/Paste, native paragraph tab layout, source persistence, and shared
Undo. It also verifies that removed preference APIs cannot affect the editor
while tag-field completion remains available. Cursor ownership, native modifier
dispatch, and the supported `NSTextFinder` client path are covered as editor
lifecycle regressions. A static preflight checks the editor defaults, the
absence of the hidden tab-width and finder compatibility paths, status-menu
structure, and shortcut help in every localization.
