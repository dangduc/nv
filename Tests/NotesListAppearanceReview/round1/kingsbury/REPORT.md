# Round 1: State-transition review

This review uses a Kyle Kingsbury-inspired state-transition lens. It does not represent a review by Kyle Kingsbury.

Reviewed revision: `2e3f75e794b668024cf54597110f13ccf2aff97a`.
Base revision: `878961a`.

No actionable introduced defect was found within the tested scope.

## Executable evidence

Command:

```sh
python3 Tests/NotesListAppearanceReview/round1/kingsbury/run.py --negative-controls
```

The native arm64 fixture passed **2,693 checks across 128 ordered transitions**.
The four negative controls each failed their intended assertion.
The compiler emitted the existing pointer-cast warning from `BufferUtils.c`.
The fixture ran on macOS 26.5.2 with Xcode 26.6.

The runner extracts these production methods and constructs two native windows:

- The notes-list construction prefix from `setupBrowserContent`.
- The `NVBrowserContentView` appearance callback and `browserAppearanceChanged`.
- `updateColorScheme` and the notes-list collapse, height, and restoration methods.
- `LinkingEditor.updateTextColors` and `LabelsListController.cachedLabelImageForWord:highlighted:`.

The runner also compiles the production preview formatter and rounded-rectangle utility.
The windows share one actual `NSTextStorage`, with a separate layout manager for each native text view.
The fixture uses fixed preferences and cursor, link, and selection-color collaborators.

## Results

| Sequence | Observed result |
| --- | --- |
| Alternate two windows through Aqua, Dark Aqua, and both high-contrast appearances | Each list, scroll view, and clip view resolves its own window colors. |
| Deliver one window callback while the peer supplies the current drawing appearance | The callback reaches only the owning controller and requests its list redraw. |
| Alternate system and custom editor colors | System editor colors resolve against the owner. Custom editor colors remain unchanged. |
| Collapse a list, change appearance, and restore the list | The production visibility method preserves the requested state and current appearance. |
| Reuse cached single-line and multiline previews across appearances | The cached body color resolves against each drawing appearance. |
| Share ordinary and selected tag images across windows | Each image matches the resolved color and alpha. Repeated colors reuse the same image. |
| Repeat all transitions with shared source and native Undo managers | Source characters and attributes remain equal. The storage delegate reports zero edits. Undo and Redo remain empty. |

The tag cache contains three distinct resolved colors after all transitions.
The four appearance variants share some colors, including the selected text color.
The cache contains exactly the color keys observed by the fixture.

The negative controls remove callback forwarding, restore a white table background, remove color from the shared tag key, and pin the list to Aqua.
Each control fails a corresponding routing, background, tag-color, or inherited-appearance assertion.

## Limits

The fixture explicitly delivers `viewDidChangeEffectiveAppearance` through the production view class.
It checks callback routing and order. It does not establish live system-notification delivery or timing.
The windows remain offscreen, and the tag checks inspect generated image pixels.
The fixture does not establish complete table-cell rendering or physical keyboard-focus behavior.

The shared text and Undo checks cover the extracted display path with real AppKit objects.
They do not instantiate `NoteObject`, the shared editing session, or library persistence.
No changed appearance method calls a library write or editing-session commit in the inspected source.
The fixture does not establish full application lifecycle behavior.

The existing Intel startup stall prevents the full desktop suites.
This review did not launch an Intel application or use personal notes.
