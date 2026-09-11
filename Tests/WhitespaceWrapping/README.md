# Trailing-space wrapping investigation

This document records the earlier whitespace change.
The [word-wrapping refinement](../WordWrapping/README.md) now preserves fitting words while retaining the ordinary-space adjustment described here.

A small layout delegate adjustment makes ordinary spaces wrap in a native `NSTextView`.
The usual text-view settings did not produce this result.
This directory contains an isolated prototype and a copied-app integration check.
The Development build now includes the adjustment in `LinkingEditor`.

## Implementation

The existing layout-manager delegate in `LinkingEditor` clears `NSGlyphPropertyElastic` for ordinary U+0020 space glyphs.
Control glyphs retain their properties.
The common note-body attributes use native character wrapping.
Words can split at the window edge, so overflowing spaces do not move an already-fitting word.
Native editing commands remain active.

Apple defines the [elastic glyph property](https://developer.apple.com/documentation/appkit/nslayoutmanager/glyphproperty/elastic) as a changeable width, with whitespace as an example.
Apple also provides a [glyph-generation delegate](https://developer.apple.com/documentation/appkit/nslayoutmanagerdelegate/layoutmanager(_:shouldgenerateglyphs:properties:characterindexes:font:forglyphrange:)) for changes to glyph properties.

The prototype clears one flag in the supplied glyph-property array.
It preserves glyph IDs, source indexes, font, and all other flags.
The glyph delegate does not replace spaces, insert newlines, or modify source attributes.
The common paragraph style configures character wrapping for source storage and typing attributes.
It does not override key handling, selection, or caret drawing.

The experiment links the elastic flag to the trailing-space layout behavior on this host.
This finding does not establish the cause of the separate intermittent left-edge caret jump on macOS 13.

## Configuration results

Each case used a 480-point view with a 464-point text container and 5-point line-fragment padding.
The input contained 201 ordinary spaces, with no newline.

| Setting | Result |
| --- | --- |
| Default TextKit 1 | One visual line. Caret remained at the right margin. |
| Character wrapping in paragraph style | Same trailing-space behavior. Normal prose changed to character wrapping. |
| Character wrapping on text container | Same trailing-space behavior. Prose retained word wrapping. |
| Character wrapping on both | Same trailing-space behavior. |
| Standard paragraph line-break strategy | Same trailing-space behavior. |
| Latest typesetter behavior | Same trailing-space behavior. |
| Original typesetter behavior | Same trailing-space behavior. Different line heights. |
| Show invisible characters | Same trailing-space behavior. |
| Horizontal scrolling, wrapping disabled | Space widths accumulated, and the view scrolled horizontally. |
| TextKit 2, word or character wrapping | Spaces stayed on one visual line. End-of-source rectangle query returned no valid rectangle. |
| Clear elastic flag for ordinary spaces | Four lines at Menlo 12; six lines at Menlo 22. Caret advanced across lines. |
| Clear elastic flag plus character wrapping | Same whitespace result; ordinary prose used character wrapping. |

The paragraph character-wrapping case is a positive control: the setting changed prose layout but did not correct trailing spaces.
Apple documents [character wrapping](https://developer.apple.com/documentation/appkit/nslinebreakmode/bycharwrapping) as wrapping before a character that does not fit.
The whitespace exception remains observable in this experiment.

Apple documents [horizontal scrolling](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/TextUILayer/Tasks/TextInScrollView.html) as a native configuration.
This option changes the editing experience because long lines require horizontal navigation.
The glyph adjustment preserves soft wrapping, so it better matches the requested behavior.

## Initial investigation evidence

Environment: macOS 26.5.2 (25F84), Xcode 26.6 (17F113).
Investigation worktree: merged master `f772c4b`.
The `Sources` and `Resources` trees match reviewed PR #24 head `6f59a94`.

Both arm64 and x86_64 under Rosetta passed:

- 11,258 source and selection checks per architecture.
- 208 case results per architecture: 13 modes, two font sizes, and eight fixtures.
- 5,226 repeated Space key events per architecture.
- Source preservation after insertion and native Backspace.
- Identical baseline layout for the initial prose, tab, and Unicode fixtures with only the elastic-flag adjustment.
  The final character-wrapping policy intentionally changes word boundaries.
- Wrapping and caret advancement for blank-space, text-prefix, Unicode-prefix, and repeated-key fixtures.

At Menlo 12, the adjusted caret after 201 spaces was `(121.369, 50)` in view coordinates.
The default caret remained at `(467, 8)`.
The adjusted layout had four lines: 62, 62, 62, and 15 glyphs.
The source still contained exactly 201 U+0020 characters.

The native text view receives repeated `NSApplication` key events with `isARepeat` set after the first event.
Each event has a source-length and selection assertion.
The loop permits deferred AppKit work between events.
Geometry queries occur after the sequence and force layout.
They do not establish the position of every displayed animation frame.

The Unicode fixture includes Vietnamese letters, a combining accent, a joined emoji, Chinese text, and nonbreaking spaces.
These limited fixtures do not establish correctness for every writing system or font.

## Run

Run these commands from this worktree in an active macOS desktop session:

```sh
python3 Tests/WhitespaceWrapping/run.py --arch arm64
python3 Tests/WhitespaceWrapping/run.py --arch x86_64
```

The second command requires Rosetta on Apple Silicon.
The standalone probe targets macOS 13 or later and uses in-memory text.
It does not open nvALT, read its preferences, or access note libraries.
Raw JSON and logs are in `build/WhitespaceWrapping/`.

## nvALT integration

Round-one review found fitting-word displacement and slow reflow in long space runs.
The paragraph character-wrapping setting addresses those interactions with native word wrapping.
The [review record](../WhitespaceWrapReview/STATUS.md) preserves each finding and its correction evidence.

The production method returns zero when a glyph batch requires no change.
It copies the property array only for batches that contain eligible spaces.
It performs no layout queries inside glyph generation because they can recurse.
The adjustment applies to U+0020 and leaves tabs, nonbreaking spaces, and control glyphs unchanged.

Run the integration check after a Development build:

```sh
python3 Tests/WhitespaceWrapping/run-app.py
```

The copied app uses temporary notes and isolated preferences.
Its 843 checks passed on the Intel Development build.
The check covers Plain Text and Markdown at Menlo 12 and 22, with 804 repeated Space events.
It also covers Backspace, shared Undo, two editor widths, and reflow after resizing.
Runtime comparisons confirm native key insertion, deletion, and insertion-point drawing methods.

## Remaining validation

Validate caret movement and mouse selection around wrap boundaries on macOS 13.7.8.
The current host runs macOS 26.5.2.
Long runs of spaces will occupy more visual lines by design.
The prototype does not establish a performance bound for every note size or font.
See [BUILD.md](BUILD.md) for the Development build and regression results.
