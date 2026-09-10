# Round 2: native appearance ownership

This contrarian review tests whether search cleanup changes appearance that belongs to native text editing or another view.

No actionable finding. The candidate preserves the tested source attributes, native selection settings, composition state, and separate layout backgrounds.

This round uses four real `NSTextView` instances. Each pair shares one native `NSTextStorage` through separate layout managers. The two pairs use opposite light and dark appearances. No window opens. The probe extracts the production invalidation observer, cleanup methods, range setter, and drawing delegate.

The candidate passes 48 checks. Four deliberate defects fail 16 assertions. The final run tested `5db853c` on macOS 26.5.2 through Rosetta. Its four production files match `c2209e2`, and their hashes remain unchanged. Compilation produced no warnings.

## Evidence

The new probe checks native objects and actual composition commands, rather than repeating the earlier attribute-dictionary matrix.

- Clearing one editor leaves another layout's search backgrounds intact.
- Stored foreground and background attributes survive temporary highlight cleanup.
- Each native view retains its selection range and selection-attribute dictionary.
- Body background, caret color, capture metadata, and temporary underlines survive cleanup.
- Calling native `setMarkedText:selectedRange:replacementRange:` establishes a real marked range and advances both extracted observers' generations.
- Deferred cleanup preserves the marked source snapshot, native marked range, selection, and marked-text configuration. Native `unmarkText` still completes composition.
- Empty results cancel pending cleanup. Missing highlight colors also retire pending work before returning to the run loop.
- Restoring a valid search color permits independent highlights in both views.

The sensitivity controls are:

| Deliberate defect | Failed assertions |
| --- | ---: |
| Remove stored source backgrounds during temporary cleanup | 2 |
| Clear every layout attached to shared storage | 10 |
| Omit immediate display suppression | 2 |
| Return for a missing search color before cleanup | 2 |

The runner rejects exceptions and process errors as control evidence. Candidate and control outputs are preserved beside `manifest.json`.

Run:

```sh
python3 Tests/SourceBackspaceReview/round2/contrarian-b/run.py
```

## Limits

These native views are windowless. The probe calls the drawing delegate directly and does not render pixels. It supplies source colors, link preferences, and capture validity through adapters.

The native composition API runs, but no actual input method or candidate window runs. AppKit retains the configured marked-text background in its configuration dictionary. This setup does not expose that background in source or temporary attributes. The probe therefore makes no claim about input-method background pixels. The logs include connection errors from the unavailable HIServices service; all asserted native composition operations complete.

Stored source backgrounds serve as a cleanup isolation test. This does not propose restoring rich-text note support. The appearance pairs test object configuration, not resolved system palette pixels. The user's macOS 13.7.8 environment remains unavailable.
