# Round 1 — measurement and framework behavior

Perspective: Dan Luu's emphasis on measured behavior; this report does not speak for him.

No actionable finding in the search field's width or resize behavior.
Reviewed `6b8d67514f4fc5bc2e9fca22816a32f30f59fb1c` against upstream `89d9abe`.
The relevant implementation is `Sources/Browser/AppController_BrowserUI.m:343–358`.

## Executable evidence

Run `python3 Tests/TitlebarReview/round1/luu/run.py` from a desktop session.
The native ARM64 fixture compiles the extracted production toolbar methods and the actual `DualField.m`.
It acquires `build/pr-review/gui.lock` before opening a disposable window.
It neither opens nor changes a note library.

On macOS 26.5.2 (25F84), all 21 geometry checks passed: seven grow/shrink steps for each of an empty query,
a 1,024-character query, and that long query with the native field editor active.
The minimum window width matches production's 480-point limit.

| Window width (points) | Search width (points) |
| --- | --- |
| 480 | 383 |
| 780 | 683 |
| 1,200 | 1,103 |
| 1,600 | 1,503 |

All cases retained an 89-point leading offset and an 8-point trailing margin.
The field already had its final width when `setFrame:display:` returned, before a separate layout call or event drain.
Shrinking produced the same geometry as growing. The native field editor stayed attached during the editing scenario.

The negative control removes only the new container and assigns `DualField` directly to the toolbar item.
It fails all 21 geometry checks: the field remains 325 points wide at every tested window width.
This supports keeping the container despite the apparent simplification offered by a direct toolbar view.

For context, 200 programmatic resizes after 20 warm-up iterations measured resize plus synchronous layout:
median 0.993 ms, p95 1.044 ms, maximum 1.073 ms for production.
The direct-field negative control measured 0.213/0.227/0.241 ms respectively, while failing geometry.
These are bounded fixture measurements, not an application performance budget or frame-rate claim.

## Reproduction identity and limits

Extracted-method SHA-256: `571488e10370d58f1282c26efd197668710cb67c53a6533a9cc8a769984ff06d`.

| Production input | SHA-256 |
| --- | --- |
| `AppController_BrowserUI.m` | `6a179cb93dfe10052bb894b077cb969a1a748862646adbe35cec4b4cdcf1a33a` |
| `AppController.m` | `46a9c9f6f0aee838d547dd7b0ef17fa80f97978e1e951ffa0dca91229dac67be` |
| `DualField.m` | `6617a4b656f5d55587ac0ee374148efdbc906772c9f3e2ace1ab9a205dd6f9c8` |

Raw geometry, timings, compiler logs, and source hashes are written under `build/TitlebarReview/round1/luu/`.
The probe has blank window content and substitutes only `DualField`'s unrelated browser-routing collaborator.
It excludes note-table, editor, preview, storage, compositor presentation, and controller lifecycle costs.
It uses programmatic resizing; it does not establish mouse-drag live-resize performance.
It does not test macOS 10.13 or other older AppKit versions.
The first sandboxed launch could not connect to desktop services; the completed measurement ran outside that sandbox.
