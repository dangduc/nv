# Round 2 correction: repeated preview transitions

Review comments:

- https://github.com/fastducduc/nv/pull/4#discussion_r3956449561
- https://github.com/fastducduc/nv/pull/4#discussion_r3956584017
- https://github.com/fastducduc/nv/pull/4#discussion_r3956609738

A loading capture now joins the pending exact read for the same library, note, and viewer.
It keeps that read's revision, cached fallback, and original 0.5-second deadline.
Each caller receives its own snapshot identity once, including after timeout or closure.
The navigation barrier remains until all joined callbacks complete.
Explicit restoration still invalidates the group, and older reads cannot replace newer state.

The browser keeps its useful saved cache while that exact read remains pending.
Its latest callback receives the shared result and updates canonical state.

The browser also keeps saved source scroll while Preview hides the source editor.
Switching to a shorter note can clamp that hidden editor's clip origin to zero.
That layout change must not replace the user's saved source position.
Window serialization uses the saved source position while Preview is active.
Before Source restores a nonzero origin, TextKit lays out through the saved viewport.
This gives the editor enough height to restore that origin without laying out the entire note.

A pending return also adopts the original capture's cached Find query when selecting that presentation.
Its later completion changes only offsets, preserving newer query state.

The workflow fixture now creates both notes before entering Preview.
Its controlled schedules use only note reveals and Source/Preview actions.
The three checks inspect saved source and viewer state, the native Find field, and visible document scroll:

- A → B → A.
- A → B → A → B → A.
- A → B → A → Source → A.

Before the source correction, the copied app preserved preview scroll 420 after A → B → A → B → A, then failed:

```text
FAIL: preview note histories preserve the source position when hidden layout changes its clip origin
```

This assertion runs before saved-window restoration. The fixture retained its source fields.
A diagnostic recorded source and saved source scroll changing from `{0, 280}` to `{0, 0}`.
The unconditional source-scroll capture caused that change after hidden editor layout.
The Source transition also exposed an incomplete layout: saved scroll was 280, but the live clip remained zero in a 234.5-point editor.
Laying out through the saved viewport increased the editor height to 562 and restored live scroll 280.
The correction probe then passed all 110 workflow checks.

A separate check set the query to `Paragraph` before A → B → A.
Preview scroll returned to 420, but the provider query and native Find field became empty:

```text
FAIL: pending presentation return retains its saved Find query in provider state and the native search field
```

Validation on macOS 26.5.2 with Xcode 26.6:

- Standalone viewer: 195 checks pass; the resource fixture receives no network requests.
- A native Find action enters a newer query after a capture starts. That newer query survives the old read; the original caller still receives its immutable query.
- New standalone checks against the reviewed `f037c7b` provider fail at the joined-state assertion, as expected.
- Copied-app checks confirm all three preview histories restore scroll 420 in both browser state and the visible document.
- The rebuilt production app passes all 110 workflow checks. Saved source scroll remains 280 and exact viewer scroll remains 420 through repeated histories.
- Saved-window restoration preserves source scroll 280 and applies the explicit viewer scroll 300. Older callbacks cannot replace that restored state.

Commands:

```sh
python3 Tests/Regression/source-viewers/run-viewer.py
python3 Tests/Regression/source-workflow/run.py
```

Local logs: `build/round2-viewer-fix-tests.log` and `build/round2-viewer-workflow-fix.log`.
The probes use the shared GUI lock, copied applications, temporary notes, and isolated preferences.
The WebKit callback boundary controls delayed delivery; production timeout and completion paths remain active.
No macOS 10.13 runtime or unbounded scheduling exploration was performed.

Historical review reports and reproduction probes remain unchanged.
