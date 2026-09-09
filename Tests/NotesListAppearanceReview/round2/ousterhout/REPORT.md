# Round 2: native appearance ownership and cache boundaries

This review uses a John Ousterhout-inspired design lens. It does not represent a review by John Ousterhout.

Reviewed revision: `755bc8b849547e6714ffaa22fbb339ad65008393`.
Comparison base: `878961a`.

No actionable introduced defect was found within this scope.

The first-round report used explicit drawing appearances.
This round adds native view attachment, AppKit callback delivery, and a cache boundary between tag measurement and drawing.

## Executable evidence

Run:

```sh
python3 Tests/NotesListAppearanceReview/round2/ousterhout/run.py --negative-controls
```

The fixture passed **323 checks** at both 1× and 2× backing scales.
Each run covered 16 native window appearance changes and 16 content attachments.
All three mutation controls failed their intended assertions in both runs.

The runner extracts these production implementations without changes to their bodies:

- The list construction prefix from `setupBrowserContent`.
- `NVBrowserContentView`, `browserAppearanceChanged`, and `updateColorScheme`.
- `LabelsListController.cachedLabelImageForWord:highlighted:`.
- The three `NoteObject` methods for tag measurement and drawing.

It also compiles the production preview formatter and rounded-rectangle utility.
Native windows, split controllers, scroll views, and a table supply the hierarchy.
Fixed collaborators supply preferences, one tag, and the library cache.
A small content view draws unchanged preview objects and calls the extracted tag drawing method.

## Results

| Boundary | Observed result |
| --- | --- |
| Change a window appearance, then resolve the editor view's effective appearance | AppKit delivers the production callback to that window's owner and requests a new list redraw. The peer owner receives no callback. |
| Move one content view between two list hierarchies | The content inherits its destination appearance without an explicit appearance property. |
| Measure a tag under the opposite ambient appearance before drawing | Measurement can populate the shared cache. Native drawing still selects the raster for its destination color. |
| Reuse cached single-line and multiline previews after each move | Both previews retain their object identities. Their native captures show contrasting body glyphs in light and dark modes. |
| Draw tags through the production left and right alignment paths | Both paths place the expected composited fill into the native capture. |
| Return to earlier appearances across owners | Equal colors reuse the same raster. The cache retains exactly two tag images. |
| Deliver appearance changes with custom editor colors | The editor retains its green background. The list redraw uses system colors. |
| Draw while the caller has the opposite ambient appearance | AppKit supplies the view appearance during capture, then restores the caller appearance. |

The first mutation removes callback forwarding. It fails the automatic-delivery assertion.
The second mutation restores the fixed Aqua appearance on the list. It fails the destination-inheritance assertion.
The third mutation removes the resolved color from the tag key. It fails after measurement populates the cache for another appearance.

## Design assessment

`NoteObject.m:1170` measures tags through the same image cache that supplies drawing at line 1202.
Measurement can occur outside a view drawing context.
The resolved color in `LabelsListController.m:120` keeps that earlier measurement from selecting the wrong raster during a later native draw.

Dynamic preview attributes need no additional invalidation for these attachment changes.
Raster images require color-specific entries because their pixels cannot resolve another appearance later.
The current boundary supports both values without coordination between browser owners.

## Limits

The host ran macOS 26.5.2 and Xcode 26.6 on Apple Silicon.
The captures contained 600×150 pixels at 1× scale and 1200×300 pixels at 2× scale.
The compiler emitted the existing pointer-cast warning in `BufferUtils.c:406`.

The fixture changes explicit window appearances and resolves `effectiveAppearance` to prompt AppKit's deferred callback delivery.
It never calls `viewDidChangeEffectiveAppearance` directly.
This evidence does not establish physical system-toggle notification timing or visible-window event dispatch.

The custom content view exercises the native drawing context and production tag methods. It does not instantiate complete production table cells.
The fixture uses one unselected tag, light and dark appearances, and custom editor colors.
It does not establish selection behavior, accent changes, library persistence, or the complete browser lifecycle.

The Intel application and browser nibs remain outside this fixture. The existing Intel startup stall prevents full desktop evidence.
No personal notes were accessed. No production files changed.

Sources, captures, and logs are under `build/NotesListAppearanceReview/round2/ousterhout/`.
