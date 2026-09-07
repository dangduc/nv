# Restoration regression canaries

After building the Development app, run:

```sh
python3 Tests/Regression/restoration/run-canaries.py
```

Run outside the process sandbox for Rosetta/Cocoa. The runner takes the shared GUI lock, copies the app, and uses temporary notes and unique preferences domains.

The current integration suite must pass first. The runner then removes saved query restoration through a guarded runtime override. The suite must fail its per-window query assertion. A second override clears the displayed search field while preserving session state; the field assertion must fail.

The fixture saves `beta` and `only` in separate browsers. Relaunch checks each session query and the DualField title/query state. It invokes available snapback controls and checks the resulting visible queries. These checks follow the field's existing behavior: a selected note displays its title and retains the search for snapback.

The runner exits zero only when the baseline passes and both mutations fail their intended assertions. It never modifies production source or the shared built app. Historical round-one evidence remains under `Tests/ReviewEvidence/round1/test_contrarian/`.
