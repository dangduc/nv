# Round 2: contrarian selection and editing review

This review challenges the assumption that inactive-window captures establish active keyboard selection.

Reviewed revision: `755bc8b849547e6714ffaa22fbb339ad65008393`.
Comparison base: `878961a`.
Production code remains unchanged since `2e3f75e794b668024cf54597110f13ccf2aff97a`.

No actionable introduced defect was found within this scope.

## New executable evidence

Run from an active desktop session:

```sh
python3 Tests/NotesListAppearanceReview/round2/contrarian/run.py --negative-control
```

The native arm64 fixture passed **193 checks** across 12 presentation states and 36 row captures.
The base-source comparison passed another **97 checks** across six states and 18 row captures.
The deliberate color mutation failed its intended assertion.

The fixture creates a temporary native application bundle and displays its own window.
AppKit reports the application as active and the window as both key and main.
The fixture checks this state again after each appearance and alternating-background change.
It never overrides `isKeyWindow`, `isMainWindow`, or `firstResponder`.

The fixture compiles the production single-line preview formatter.
It extracts the unchanged production `tableView:willDisplayCell:forTableColumn:row:` delegate method.
Native `NSTableView`, `NSTextFieldCell`, `NSScrollView`, and field-editor objects supply drawing and focus behavior.
Fixed preferences and three temporary rows replace the library and browser session.
The data-source collaborator matches the ordinary-list preview selection policy.

Each Aqua and Dark Aqua case runs with plain and alternating backgrounds.
Each case covers three states:

1. The selected row has keyboard focus in the active table.
2. AppKit opens the actual table field editor for that row.
3. A separate text field receives focus after the table edit ends.

The checks establish these bounded results:

- Ordinary row backgrounds follow the window appearance.
- Selected and unselected title glyphs contrast with their row backgrounds outside inline editing.
- Preview glyphs contrast in active and inactive selection states.
- AppKit assigns the field editor to the requested row and makes it the first responder.
- Each focus transfer ends the table edit and calls the data-source commit method exactly once.
- Dark inline-editor title glyphs contrast with the field background.

The captures use the native view drawing context without an explicit drawing-appearance block.
The pixel counts exclude the caret and focus-ring borders.
The inline-editor measurement samples its own background, away from the animated table selection.
These measurements establish visible glyph differences, not an accessibility contrast guarantee.

The negative control replaces the delegate's ordinary `labelColor` with fixed black.
It fails the first dark unselected-title glyph assertion.
The runner restores the extracted delegate and rebuilds the normal fixture afterward.

## Excluded observation

The light inline-editor fixture produces white title text on a white field background.
The glyph count inside the title bounds is zero with both background settings.
This behavior also occurs with the base formatter and the exact base delegate.
The runner compares the two light observations, including resolved colors and glyph visibility. They match exactly.

This observation does not establish an introduced PR defect.
The color delegate at `Sources/Browser/AppController.m:1935` is unchanged by this PR.
The fixture calls native `editColumn:row:withEvent:select:` directly and replaces the editor contents with the title.
It does not compile the complete production inline-edit override or dispatch the original key event.

The inspected production Return-key path requests inline editing at `Sources/UI/NotesTableView.m:927`.
The Rename action instead selects the top title field at `Sources/Browser/AppController.m:621`.
The fixture does not establish which additional application behavior affects the observed light inline editor.
No production correction is proposed from this observation.

`UnifiedCell` is outside the final fixture and its result.
`NotesTableView.browserHorizontalLayout` returns `NO`, so the current list uses ordinary cells.

## Limits

Host: Apple Silicon, macOS 26.5.2, Xcode 26.6.
The native captures use 2× backing pixels.
The compiler emitted the existing pointer-cast warning in `BufferUtils.c:406`.

The initial sandboxed application startup aborted before assertions. The completed runs used desktop access.
The runner requires a desktop session that permits the temporary application to activate.
Other applications can interrupt that focus requirement.

The fixture changes explicit window appearances. It does not change system preferences or establish physical system-toggle timing.
It does not exercise tag columns, browser nibs, real note commits, or the top metadata fields.
The Intel application remains outside this fixture because the host has the existing startup stall.
No personal notes were accessed. No production files changed.

Sources, captures, and logs remain under `build/NotesListAppearanceReview/round2/contrarian/`.
