# Native source editing regression

`run.py` launches a copied Development app with an isolated library. It checks
that the source editor delegates ordinary editing commands to `NSTextView`.

Build the Intel Development app, then run:

```sh
python3 Tests/SourceEditing/run.py
```

The native probe covers Return, Backspace, Tab, character pairs, word
selection, title completion, spelling, writing direction, source persistence,
and shared Undo. It also verifies that removed preference APIs cannot affect
the editor.
