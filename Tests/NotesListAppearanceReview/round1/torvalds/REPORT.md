# Round 1: correctness and maintenance review

Review lens: Linus Torvalds-inspired correctness and maintenance. This report does not represent a review by Linus Torvalds.

Baseline: `2e3f75e794b668024cf54597110f13ccf2aff97a`, compared with `878961a`.

No actionable introduced defect was found within this review scope.

## Evidence

Run:

```sh
python3 Tests/NotesListAppearanceReview/round1/torvalds/run.py --negative-controls
```

The corrected native fixture passed 3,836 assertions at 1× scale and 13,564 at 2× scale.
These counts include individual pixel checks. Both runs also passed with `NSZombieEnabled=YES`.
The fixture extracts these production methods from `LabelsListController.m`:

- `cachedLabelImageForWord:highlighted:`
- `invalidateCachedLabelImages`
- `dealloc`

It also compiles the production `NSBezierPath_NV.m` implementation.
The `GlobalPrefs` collaborator supplies a configurable font size.

The checks establish these bounded properties:

- Cached images survive autorelease pool drainage. Cache invalidation releases its images.
- Caller retention preserves an image after controller disposal. The final caller release disposes that image.
- Equal color values reuse an image. Different alpha values produce different images.
- Translucent tag fills preserve their alpha. Glyph coverage removes that fill in explicit Aqua and Dark Aqua appearances.
- Four system appearances and both selection states reuse a bounded set of images across 24 cycles.
- Tag generation preserves the caller graphics context and compositing operation.
- Font invalidation produces image dimensions for the new font size.

The appearance cases include Aqua, Dark Aqua, and their increased-contrast variants.
The alpha checks temporarily replace `secondaryLabelColor` inside the isolated fixture process.
Image-associated release witnesses record disposal without changing image ownership.

Three deliberate mutations failed their intended assertions:

| Mutation | Detected consequence |
| --- | --- |
| Omit the color from the cache key | Different alpha values reuse one image. |
| Restore `SourceOut` compositing | Glyph coverage does not remove the expected fill. |
| Omit the image autorelease | Cache invalidation does not release its images. |

The extracted production methods also compile for Intel with a macOS 10.13 deployment target.
Availability diagnostics are errors in that compile. No diagnostics occurred.
The extracted methods add no unsupported API to that target.

Logs are in `build/NotesListAppearanceReview/round1/torvalds/`.

## Fixture correction after the aggregate run

The first aggregate run reported a false pixel failure in this fixture.
The sandbox supplied 52×18 backing pixels for a 52×18-point tag.
Desktop access supplied 104×36 backing pixels for the same tag.
The original fixture compared a downsampled 2× tag with an independently rasterized 1× glyph mask.
These masks had different antialiasing coverage. At the reported pixel, the 1× mask was opaque while the tag retained alpha 0.1647.

The corrected fixture draws both images on matching AppKit surfaces and compares their native backing pixels.
It checks the alpha equation `fillAlpha * (1 - glyphCoverage)` and retains the original 0.04 error limit.
It also retains the explicit opaque-pixel removal check.
Native pixels avoid downsampling overshoot, which produced alpha 0.7529 from a 0.70 fill during diagnosis.

The corrected fixture passed in both environments, including the zombie runs and all three mutation controls.
The obsolete `SourceOut` operation still failed the glyph-coverage assertion.
No production code changed. The review conclusion remains unchanged.

## Limits

Host: Apple Silicon, macOS 26.5.2, Xcode 26.6.
The fixture exercises actual AppKit raster drawing and the extracted cache methods under manual memory management.
It does not launch the Intel application or load browser nibs.
The compatibility compile does not establish runtime behavior on macOS 10.13.
The appearance cases do not establish physical system-toggle notifications or keyboard-focus behavior in browser windows.
The host's existing Intel startup stall prevents those full application checks.
