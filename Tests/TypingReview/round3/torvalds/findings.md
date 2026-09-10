# Round 3: implementation and resource boundaries

This review uses a Linus Torvalds-inspired implementation perspective. It does not represent Linus Torvalds or his authorship.
Reviewed PR #24 at `d93f93521beb4cd9f6e7d2ba77000eb2bcb41bd6`, against `8dde5e8`.
The production revision is `5eda58b`. I read `AGENTS.md`, `architecture.md`, and the earlier reports.
I changed no production files.

No confirmed defect was found in this scope.

## Executed evidence

```sh
python3 Tests/TypingReview/round3/torvalds/run.py
```

Result: **80 cases and 4,940 checks passed**, with exit 0 and no sanitizer diagnostic.
All three negative controls failed on case 1 at the intended assertion.
The environment was macOS 26.5.2, Xcode 26.6 (17F113), and the Intel target under Rosetta.
The build uses manual reference counting, AddressSanitizer, and UndefinedBehaviorSanitizer.

The runner extracts three complete production methods from `LinkingEditor.m`:

- `highlightLinkAtIndex:`
- `clickedOnLink:atIndex:`
- `menuForEvent:`

It also extracts `sourceCharactersChanged:` from `NVNoteEditingSession.m` and both storage-state functions from `NVSourceAnalysis.m`.
Native `NSTextStorage` notifications call the extracted session method.
Native `NSTextView`, layout managers, text containers, selections, and attribute mutations supply the application boundary.
The fixture records analysis requests and invalidations without a worker.

| Probe | Result |
| --- | --- |
| Two editors share storage, then native character insertion invalidates links | Both editors rejected obsolete targets. The session advanced its generation and requested analysis once. |
| Stale direct clicks with HTTP and nvALT targets | No target reached the external or internal action boundary. Caret positions stayed within the current source. |
| Indexes at zero, final character, source length, `NSNotFound`, and `NSUIntegerMax` | Stale highlights preserved selection. Stale clicks clamped their caret positions. |
| Context-menu construction after invalidation | The superclass boundary saw no links. Cleanup preserved source and an unrelated application attribute. |
| One native layout moves to another storage | That editor used the new current link. The peer remained attached to the old stale storage. |
| Current targets after the layout move | All 80 external actions and 80 internal actions reached their recorded boundaries. Current menu construction preserved links. |
| Storage becomes empty | Current highlights returned nil without index underflow. Stale clicks stayed at zero. Menu cleanup accepted the empty range. |
| Repeated construction and teardown | Eighty cases constructed and released two native editors. The corpus includes ASCII, empty strings, surrogate pairs, combining marks, CJK, joined emoji, and CRLF. |
| Negative control removes the stale highlight guard | Case 1 failed: `stale highlight must reject target`. |
| Negative control removes the stale click guard | Case 1 failed: `stale clicks cannot reach external or internal action boundary`. |
| Negative control removes the stale menu guard | Case 1 failed: `superclass menu boundary sees zero obsolete targets`. |

The run crossed 240 menu boundaries in total.
Saved evidence is in `output.txt` and `results.json` beside this report.
Generated source, binaries, and compile logs are under `build/TypingReview/round3/torvalds`.
The SHA-256 for the three extracted editor methods is `45690ff2829401497d516f8ee2f6c7a4d1ee34b213eb8bd90be5acf69696673e`.

## Code conclusions and limits

`LinkingEditor.m:438-465` rejects stale actions before target dispatch and bounds stale caret positions against current source length.
`LinkingEditor.m:489-496` removes stale attributes before it calls the superclass menu method.
`NVNoteEditingSession.m:153-161` invalidates the shared storage state on processed character edits.
The storage association follows each native layout across a note switch.
The fixture uses the same remove/add layout operations as `AppController.m:1197-1199`.

This probe intercepts superclass menu construction and final URL actions.
It does not create or track an actual Cocoa menu, activate an existing menu item, or open a URL.
Thus it does not establish behavior after a menu already captures a current target and a later edit invalidates that target.
It does not run full browser attachment, source analysis, syntax changes, window closure, or the application controller.
The current-link preference fixture always permits clicks. Modifier-key behavior remains outside this scope.
Empty storage and extreme indexes broaden the boundary checks beyond normal click events.
System framework internals lack sanitizer instrumentation, and leak detection is disabled.
