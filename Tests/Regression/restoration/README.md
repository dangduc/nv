# Restoration regression canaries

After building the Development app, run:

```sh
python3 Tests/Regression/restoration/run-canaries.py
```

Run outside the process sandbox for Rosetta/Cocoa. The runner takes the shared GUI lock, copies the app, and uses temporary notes and unique preferences domains.

The current integration suite must pass first. Three guarded runtime overrides then remove behavior independently:

- Discard each saved query. The per-window query assertion must fail.
- Clear the displayed search field while preserving session state. The field assertion must fail.
- Substitute archived bodies with equal-length text. The exact restored-body assertion must fail.

The fixture saves `beta` and `only` in separate browsers. Relaunch checks each session query and the DualField title/query state. It invokes available snapback controls and checks the resulting visible queries. A selected note displays its title and retains the search for snapback.

Before quitting, the fixture types ` persisted edit` through Beta's Cocoa editor. Relaunch must restore `beta only persisted edit`. Equal-length substitution preserves the existing write-verification length check, so the canary tests semantic body preservation.

The runner exits zero only when the baseline passes and all three mutations fail their intended assertions. It never modifies production source or the shared built app. Historical review evidence remains under `Tests/ReviewEvidence/`.
