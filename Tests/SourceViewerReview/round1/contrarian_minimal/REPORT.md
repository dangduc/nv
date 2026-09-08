# Round 1: complexity deletion advocate

Reviewed PR #4 at `5e44a909bd6b7b2ad1957c475f94594e0bffd461`, against `origin/master`.
This contrarian perspective challenges retained complexity. It does not assume that fewer classes always produce a better design.

## Finding CM1 — P3: remove the resources left by the deleted preview window

The old `MarkupPreview.xib` was the only consumer of `HUDIconLock.png`, `HUDIconPrint.png`, `HUDIconSave.png`, and `HUDIconShare.png`.
This change removes that interface, but retains all four images in the Xcode Resources build phase.
Each Development build still ships **113,217 unused bytes** from those images.
The current source and interface files contain no references to these images.

Evidence code: `audit-assets.py` parses the actual Xcode project, checks the built app bytes, searches current source and interfaces, and checks the former interface in `origin/master`.
Its output is recorded in `assets-output.log`.
The four resource entries are at `Notation.xcodeproj/project.pbxproj:2027–2030`; the deletion of `MarkupPreview.xib` in the same project's resource phase provides a suitable diff anchor.
Remove the four files and their build, file-reference, and navigator entries.

The audit also found a 59,369-byte orphan `Resources/Interfaces/SaveHTMLPreview.nib`, with the removed `shareNote:` connections.
It has no source or Xcode reference and does not ship. Remove it with this cleanup.
This orphan is supplementary cleanup evidence, rather than a separate newly introduced runtime regression.

## Tested concerns rejected

`python3 Tests/SourceViewerReview/round1/contrarian_minimal/run.py` exited 0 with **270 checks** on macOS 26.5.2.
It compiled a new Objective-C probe into a copied app with disposable notes and a separate defaults domain.
It used `build/pr-review/gui.lock` and did not contact external services or use personal notes.

- Opening a browser, selecting a source note, and choosing Markdown syntax allocate no preview controller.
- A Markdown-looking new note starts with explicit Plain Text syntax.
- The live main and status menus contain none of the removed sharing, sticky-preview, custom-folder, rich-style, or Marked actions.
- Calling menu setup twice leaves exactly three viewer choices and five syntax choices.
- Actual responder-chain Undo resolves to `NSWindow`, is disabled in Preview, and leaves source unchanged even when dispatched directly.
- Returning to Source preserves the prior source Undo operation.
- The application-routed HTML viewer choice leaves Markdown insertion syntax unchanged.

No behavioral bug was demonstrated in these tested routes.
The provider protocol and independent syntax/viewer choices serve the accepted extension boundary, so their existence alone is not a finding.

## Commands

```sh
python3 Tests/SourceViewerReview/round1/contrarian_minimal/audit-assets.py
python3 Tests/SourceViewerReview/round1/contrarian_minimal/run.py
```

The asset audit records the pre-fix condition and must be updated to assert absence after CM1 is fixed.
