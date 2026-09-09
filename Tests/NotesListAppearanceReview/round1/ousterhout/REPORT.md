# Round 1: appearance ownership and cache design

The John Ousterhout-inspired design lens found no actionable introduced issue in this scope. This report does not represent a review by John Ousterhout.

The review compares `2e3f75e794b668024cf54597110f13ccf2aff97a` with `878961a`. It covers appearance ownership, shared caches, and dependence on editor colors.

## Evidence

Run the native fixture:

```sh
python3 Tests/NotesListAppearanceReview/round1/ousterhout/run.py --negative-controls
```

The fixture passed **89 assertions** on arm64, macOS 26.5.2 (25F84), and Xcode 26.6 (17F113). Both negative controls failed at their intended assertions.

The fixture compiles the production preview formatter. It extracts three production methods without rewriting their bodies:

- `LabelsListController` supplies tag images and cache invalidation.
- `AppController` supplies `updateColorScheme`.

The fixture uses native AppKit colors, attributed strings, image drawing, a table view, and a text view. Fixed preferences supply font settings. Small control collaborators replace the full browser owner and editor color callback.

Eight interleaved appearance contexts share one tag cache and two unchanged preview objects. The contexts cover Aqua, Dark Aqua, and both high-contrast appearances.

The assertions establish these bounded results:

- Equal resolved colors reuse a tag image. Different colors receive different images, including selected variants.
- Repeated appearances add no redundant cache entries. Font invalidation clears every appearance variant and regenerates the larger image.
- Both preview formats resolve the current secondary label color. Their title colors remain under cell control.
- Preview formatting leaves the source text and its custom red attributes unchanged.
- The list uses its system background. The editor retains its custom green background through all eight requests.

The first negative control removes the color from the tag key. It fails the assertion that different resolved colors require different images.

The second negative control connects the list background to the editor background. It fails the assertion that the list ignores custom editor colors.

Logs and generated files remain under `build/NotesListAppearanceReview/round1/ousterhout/`.

## Design assessment

The cache boundary matches the stored value. Attributed previews retain dynamic colors, while raster images use resolved colors as key components.

This change preserves the existing library-owned image cache. It does not require another cache per window or appearance-change coordination between browser owners.

`Sources/Browser/LabelsListController.m:120` resolves the raster color before the cache lookup. `Sources/Browser/AppController.m:2152` keeps the list background independent of editor settings.

## Limits

The fixture supplies each drawing appearance explicitly. It does not establish that real window notifications arrive or that every full-app drawing path supplies the correct context.

The fixture creates native tag images but does not measure their final glyph contrast. It does not alter accent settings or exercise a Retina transition.

The probe does not launch the Intel application, load browser nibs, or access personal notes. The known Intel startup stall prevents full desktop evidence.
