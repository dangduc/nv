# Round 1: viewer boundaries and helper recovery

This review uses a John Ousterhout-inspired perspective without impersonation.
It examines module ownership, the viewer interface, menu consistency, and helper failure recovery.
No actionable defect appeared in these boundaries.

The reviewed commit is `4467e7a7251ff3846c6d255db3bd64f465fda6b2`.
The comparison base is `f3a8abb2b7942d06ec33af64b4946cfd1b6db163`.
The native probe passed **72 assertions**, including four launch-isolation checks.
The count includes repeated assertions across four formats and two helper failure cases.

## Executable evidence

Run the probe from the preview worktree:

```sh
python3 Tests/OrgPreviewReview/round1/ousterhout/run.py
```

The [launcher](run.py) copies the built app and assigns a unique preferences domain.
The app uses temporary notes, support files, and helper fixtures.
The launcher holds the common `build/pr-review/gui.lock` during the native run.
The [evidence manifest](evidence.json) records the app, helper, and production source hashes.

The [probe](probe.inc) calls production browser, renderer, provider, and editor methods.
It uses a real WebKit view and the bundled converter.
Only startup isolation hooks and the helper fixture differ from a normal launch.
The helper changes occur inside the disposable app copy.

The [output](output.txt) covers these behaviors:

- Menus and the popup expose the same four formats. Every advertised format renders through the actual provider.
- Each format has one checked menu item, and the popup follows that choice.
- Org renders a note with Plain Text syntax and leaves its source metadata unchanged.
- Two browser editors retain one shared storage. A viewer change leaves the peer in Source mode.
- Saved browser state restores Org after HTML and Source mode.
- A missing helper produces `NVMarkupHelperUnavailable` through the actual renderer and provider.
- A fixture helper exits with status 27. Its status and diagnostic appear in the error message.
- Both failures hide the old web document and remove the old export result.
- Export, print, and viewer Find become unavailable during either failure.
- Source characters, caret, source generation, modification date, and Undo history survive these transitions.
- The peer source editor remains visible and attached during either failure.
- The original helper restores successful Org rendering through the same browser after the failures.

## Boundary assessment

The browser owns the viewer selection and controls. Source syntax remains a separate note property.
The provider accepts an immutable source snapshot and a viewer identifier.
Org adds a converter choice to the existing renderer interface.
It does not introduce another mutable note buffer or format-specific process owner.

The Rust adapter holds its parse tree and list state within one converter process.
Its output handler changes presentation details and delegates other elements to Orgize.
Input and output limits remain at the converter boundary.
The application retains the existing process, cancellation, error, sanitizer, and publication paths.
The failure probe demonstrates that the Org converter uses those existing paths.

The format identifiers remain duplicated in menus, restoration, and renderer dispatch.
The executable checks found no inconsistency that requires a registry refactor in this PR.

## Limits and probe correction

The successful run used macOS 26.5.2 and Xcode 26.6, with the Intel app through Rosetta.
It does not establish runtime behavior on macOS 10.13.
The state check restores a window within one process. It does not perform an app relaunch.
The failures cover a missing executable and a controlled nonzero exit, not every process failure.
Export, print, and Find checks inspect production command availability. They do not open those panels.
The probe does not assess broad Org fidelity, large-note performance, composition, or Undo after a source edit.

The initial [failed run](initial-stale-provider.txt) inspected the old provider after window restoration.
Restoration correctly discards that provider and creates another one.
The corrected probe reads the current provider from the browser, then passes the restoration and recovery checks.
No production files changed for this review.

