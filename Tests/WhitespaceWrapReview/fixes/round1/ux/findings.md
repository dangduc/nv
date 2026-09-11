# Round 1 P2 correction: native character wrapping

The rebuilt app corrects both fitting-word displacement cases.
The probe uses the actual production app, with no runtime change to its glyph or paragraph configuration.
The production source attributes now use `NSLineBreakByCharWrapping`.
The elastic adjustment still gives ordinary spaces their font width.

The copied Intel app passed 223 checks on macOS 26.5.2 (25F84), under Rosetta.
Its binary SHA-256 was `ce1abfa2bcda08415d726352a2575412bfabb2e9f4c640a5519db7e1276beacc`.

At Menlo 18 in a 560-point window, both source prefixes fill their first visual line with appended spaces:

| Prefix | Spaces before key event | Final word before/after Space | Caret before Space | Caret after Space |
| --- | --- | --- | --- | --- |
| `alpha beta` | 39 | (70.021, 0) | (544.009, 8) | (23.837, 29) |
| `one two three four alpha beta` | 20 | (275.923, 0) | (544.009, 8) | (23.837, 29) |

The actual Space key event appends one source character.
The final word remains in place, and the caret advances near the next line's left edge.
Native Backspace deletes only that space and restores the original caret geometry.
The original round-one reproduction remains unchanged in `round1/contrarian_ux/`.

The probe also sends 201 actual Space key events, with repeat flags after the first event.
All source lengths and logical selection positions remain correct.
The resulting line lengths are 49, 49, 49, 49, and 5 characters.
The final caret is `(67.185, 92)` in text-view coordinates.
The committed note contains exactly 201 U+0020 spaces.

The Helvetica 14 fixture keeps its fitting `beta` word on the first line while the trailing spaces wrap.
A font change preserves character wrapping, native line spacing, and native tab-stop values.
Those style checks do not cover every tab layout or user-authored paragraph attribute.
Broader shared-window, Undo, and lifecycle checks remain for subsequent reviews.

This correction intentionally changes source display to character wrapping.
Ordinary words can now split across visual lines.
The source characters and native editing commands remain unchanged.

## Reproduce

After the Development build, run:

```sh
python3 Tests/WhitespaceWrapReview/fixes/round1/ux/run.py
```

The runner holds the shared GUI lock and uses an isolated copied app, disposable notes, and private preferences.
Generated geometry, logs, and the screenshot are in `build/WhitespaceWrapReview/fixes/round1/ux/`.
The committed `results.json` retains the binary identity and exact observed geometry.

The screenshot comes from the actual window's native view hierarchy.
It contains the frame controls, source text, and caret, without an external desktop background or window shadow.
These automated checks do not establish frame timing or macOS 13 behavior.
