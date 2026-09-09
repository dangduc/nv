# Round 2: tag consumer correctness review

This review uses a Linus Torvalds-inspired correctness and maintenance lens. It does not represent a review by Linus Torvalds.

Reviewed revision: `755bc8b849547e6714ffaa22fbb339ad65008393`.
Comparison base: `878961a`.
Production code remains unchanged since `2e3f75e794b668024cf54597110f13ccf2aff97a`.

No actionable introduced defect was found within this review scope.

## New executable evidence

Run:

```sh
python3 Tests/NotesListAppearanceReview/round2/torvalds/run.py --negative-controls
```

The native fixture passed **48 destination scenarios**. Both mutation controls failed their intended assertions.
The same scenarios also passed with `NSZombieEnabled=YES`.
Each normal run completed 9,248,296 checks, mostly individual pixel comparisons.
The maximum observed color-composition error was 0.001953 on a zero-to-one channel scale.
The error limit is 0.009.

The fixture extracts these production methods without changing their bodies:

- `NoteObject.sizeOfLabelBlocks`
- `NoteObject.drawLabelBlocksInRect:rightAlign:highlighted:`
- `NoteObject._drawLabelBlocksInRect:rightAlign:highlighted:getSizeOnly:`
- `LabelsListController.cachedLabelImageForWord:highlighted:`
- `LabelsListController.invalidateCachedLabelImages`
- `LabelsListController.dealloc`

It also compiles the production rounded-rectangle utility.
Small collaborators supply the font size, four ordered tag names, and the delegate that exposes the shared label cache.
The tag names include accented and Japanese characters.

The scenarios cover three font sizes: 11, 15, and 24 points.
Each font size runs under Aqua, Dark Aqua, and their increased-contrast variants.
Each appearance runs both selection states on explicit 1× and 2× bitmap destinations.

Each scenario draws the tags on four matching surfaces: transparent, opaque, right-aligned, and clipped.
The opaque surface uses the system background for the corresponding selection state.
The checks establish these bounded properties:

- Source-over composition preserves an opaque row, including transparent pixels in the tag images.
- The observed color follows the source-over equation against that row background.
- Left and right alignment produce the same pixels for the same tag group bounds.
- The destination clip preserves all pixels outside its bounds.
- The destination clip retains the included tag pixels.
- Destination drawing creates no additional cache variants after the first draw.

The first mutation changes the consumer operation from `SourceOver` to `Copy`.
It fails because transparent image pixels erase the opaque row.
The second mutation changes the right-alignment gap from four points to seven points.
It fails the pixel-equivalence assertion for left and right alignment.

Generated sources and logs remain in `build/NotesListAppearanceReview/round2/torvalds/`.

## Assessment and limits

The new cache colors reach the existing tag consumer without a second tint or an incompatible destination operation.
The consumer uses source-over drawing in `Sources/Model/NoteObject.m:1212` and `Sources/Model/NoteObject.m:1231`.
The changed generator removes glyph coverage from the image in `Sources/Browser/LabelsListController.m:147`.
Those operations preserve the row background through transparent image pixels in this fixture.

This probe extends round one from image generation to the production consumer and its destination context.
It does not repeat the independent glyph-mask comparison from round one.
All destination comparisons use matching bitmap dimensions and drawing transforms.
The probe does not compare a downsampled Retina image with an independently rasterized 1× mask.

Host: Apple Silicon, macOS 26.5.2, Xcode 26.6.
The fixture uses native AppKit and manual memory management.
It supplies appearances and selection states directly.
It does not establish full table-cell behavior, physical display transitions, live appearance notifications, or keyboard-focus behavior.
It does not launch the Intel application, load browser nibs, or access a notes library.
The existing Intel startup stall prevents full desktop evidence.
