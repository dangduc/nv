# Stale link click regression

The round-one UX review found that pending link analysis discarded ordinary caret-placement clicks.
The editor now treats stale link attributes as plain text and clamps the clicked index to the source length.
It still blocks navigation through an obsolete target.

Run the exact production callback without a desktop session:

```sh
python3 Tests/TypingReview/fixes/link-click/run-headless.py
```

This checks URL and note targets with both clickability settings and both command-key states.
It also checks empty text, invalid indices, and current link navigation.
Two negative controls restore the old early return or remove stale-target protection.
Both must fail.

After building the Development app, run the copied-app test from a desktop session:

```sh
python3 Tests/TypingReview/fixes/link-click/run.py
```

This extends the original failing native probe. It sends actual mouse events through `NSApplication`.
It also verifies context-menu cleanup, current-link restoration, word counts, and note switching.
The final native link-opening handler is intercepted so the test never opens a browser.
The runner uses only a copied app, temporary notes, and a separate preferences domain.

The original failing round-one evidence remains unchanged under `Tests/TypingReview/round1/contrarian_ux/`.

The integrated Development app passed all 26 native checks on macOS 26.5.2 under Rosetta.
See `native-output.txt`. Its executable SHA-256 was `d2fc91aab87fbb3937073e11908832d177559761e46237ecd597a3bd9ca5ec80`.
The headless run passed 13 checks and both negative controls.
