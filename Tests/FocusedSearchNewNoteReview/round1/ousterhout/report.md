# Round 1: explicit title boundary

Review perspective: John Ousterhout-inspired abstraction and coupling analysis. This report does not claim his authorship.

Reviewed commit `504f30353275663d5174656b03805625275e603a` against `b289ba3` and the browser ownership rules in `architecture.md`.

No actionable findings.

`newNote:` captures a copied title before editing completion or query changes (`AppController_BrowserUI.m:319`).
The explicit helper receives that title separately from browser search state (`AppController.m:1602`).
The original helper still supplies the field value for existing implicit-creation callers (`AppController.m:1598`).
Both helpers preserve an existing current note. Note creation still uses the shared library and existing ownership rules.

## Executed evidence

```sh
python3 Tests/ViewControlsReview/run-probe.py \
  --probe Tests/FocusedSearchNewNoteReview/round1/ousterhout/probe.inc
```

Result: exit 0; **20 checks passed**, including three setup checks. See `run.log`.

The probe verifies these boundaries in a copied Intel app with disposable notes and preferences:

- An explicit title overrides an unrelated field value and survives mutation of its caller-owned string.
- Creation does not rename or duplicate an existing current note.
- The original helper preserves query-derived titles and body text entered before implicit creation.
- Nil and empty explicit titles use the default title despite an unrelated query.
- New Note preserves the focused live string when it differs from the submitted query.
- A one-shot field mutation during `finishEditing` cannot replace the captured title.
- The new note has an empty body and cleared query; deferred callbacks do not create another note.

The last case uses a temporary method swap inside the copied process. It restores the production method before invoking it.
The synthetic mutation tests ordering at the boundary; it does not represent a reported user workflow.
Each direct helper case resets the disposable empty editor storage to isolate its input.

Binary SHA-256: `ffd2506757bfb23cfc26450ce1a736a578babd22af606a313427a6db7e399c43`.

The sandboxed launch exited before it produced app output. The desktop-capable launch completed after fixture corrections.
Those corrections handled attributed-string comparison and restricted the mutation to one boundary call.

This probe does not measure performance, test hardware keyboard delivery, or validate input methods.
It exercises controller actions and helper contracts. The maintained New Note suite supplies separate Command-N menu coverage.
