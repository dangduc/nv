# Round 2: source API and ownership review

This review uses a John Ousterhout-inspired perspective without impersonation.
It examines the source syntax API, metadata ownership, and lazy session initialization.

No actionable defect appeared in these boundaries at `4dab02a9020ff8f76cceeffc75a001927255a17e`.
The comparison base is `f3a8abb2b7942d06ec33af64b4946cfd1b6db163`.

The copied production app passed **144 assertions**, including four checks for isolation.
The host ran macOS 26.5.2 and Xcode 26.6, with the Intel app through Rosetta.
The [evidence manifest](evidence.json) records the executable hash, source hashes, environment, and exit status.

## Executable evidence

Run the probe:

```sh
python3 Tests/OrgSourceReview/round2/ousterhout/run.py
```

The [probe](probe.inc) runs the real application, note, session, and menu methods.
The [launcher](run.py) copies the app and isolates its preferences, notes, and support directory.
It holds `build/pr-review/gui.lock` during the desktop run.
The inherited launch hooks replace setup paths and suppress external-editor initialization.
They do not replace the production methods under review.

The [output](output.txt) covers these contracts:

- Both source menus and the popup expose the same six syntax identifiers.
- Each syntax action sets the model and popup, with exactly one checked item per menu.
- Effective changes send one notification. Repeated choices send none.
- Unknown, uppercase, numeric, and nil API input select Plain Text without duplicate notifications.
- Syntax changes preserve unrelated metadata, source characters, modification dates, filenames, and Undo history.
- Source syntax selection preserves the independent preview choice and Source mode.
- An unopened note restores Org from archived metadata keyed by its UUID.
- Its first session creates Org links before any layout attaches.
- A session without layouts refreshes links after syntax changes without a new source generation.
- A closed session stops receiving syntax notifications.
- A different metadata store keeps the same UUID independent.

## Boundary assessment

`NoteObject` validates the syntax identifier and owns its local metadata contract.
`NVNoteEditingSession` observes that contract and owns link attributes in shared source storage.
The browser forwards user choices and updates its controls.
No second metadata owner or source buffer appeared in this change.

The syntax choices remain duplicated in existing menus and model allowlists.
The executable matrix found no missing or extra choice.
A future registry can reduce those edits, but this review found no present defect that requires that refactor.

## Limits

The assertion count includes repeated checks across six choices and two menus.
It is not a count of independent scenarios.
The archive check restores objects in the same process. It does not simulate a full app relaunch.
The session checks use no attached layouts and avoid the visible-editor Undo failure documented in round 1.
Parser fidelity, scanner state, highlighting performance, and rendered preview behavior are outside this probe.
The first sandboxed launch stopped before any assertion. The successful run used desktop access for the same disposable app.

