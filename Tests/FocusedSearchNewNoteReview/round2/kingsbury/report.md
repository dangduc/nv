# Round 2: Kyle Kingsbury-inspired review

This is an independent review perspective, not a claim of authorship by Kyle Kingsbury.
Reviewed application commit `504f303` against `b289ba3`; `7d2a667` adds round-one review evidence only.
Cross-read all five round-one reports and probes before selecting this file-storage boundary.

No actionable findings introduced by this PR.

## Executable evidence

The new probe uses separate text-file storage in a copied app with disposable notes.
It dispatches Command-N twice through the native application menu, once in Exact mode and once in Fuzzy mode.
Both commands receive the same literal live input, which differs from the submitted query.
The title contains leading and trailing spaces, quotes, a slash, a colon, composed Unicode, and emoji.
Each new note starts empty, receives different source text through its native editor, and checkpoints to a separate file.

**44 checks passed** across two launches: 29 first-launch checks and 15 second-launch checks, including four setup assertions.
The two notes keep distinct UUIDs and filenames.
The second creation does not overwrite the first note's model or backing file.
After reopening, both notes retain their raw titles, original UUIDs, distinct filenames, and exact source bytes.

```sh
python3 Tests/ViewControlsReview/run-probe.py \
  --probe Tests/FocusedSearchNewNoteReview/round2/kingsbury/probe.inc \
  --prefix Tests/FocusedSearchNewNoteReview/round2/kingsbury/prefix.h \
  --launches 2
```

Result: exit 0; see `output.txt`.
The runner serializes desktop probes with `build/pr-review/gui.lock`.
App executable SHA-256: `ffd2506757bfb23cfc26450ce1a736a578babd22af606a313427a6db7e399c43`.

## Pre-existing observation: decomposed filename reconciliation changes the title

A variant replaces the composed `é` with `e\u0301` in the otherwise identical title.
Both creations preserve the literal title before reopening.
On reopening, directory reconciliation reports normalized filenames as renamed files.
The first note retains its UUID, but its title changes from `  "garden" / notes: Cafe\u0301 📝  `
to `  "garden" / notes- Café 📝  `.
The equality oracle compares the complete UTF-8 data, so this observes both the normalization and the colon-to-hyphen change.

The retained legacy `createNoteIfNecessary` query-title entry point produces the same failure with the same input.
Its control uses Exact mode to keep the legacy helper's post-creation selection synchronous.
Both variants pass 34 assertions before the raw-title preservation assertion fails on the second launch.

```sh
NV_KINGSBURY_DECOMPOSED_TITLE=1 \
python3 Tests/ViewControlsReview/run-probe.py \
  --probe Tests/FocusedSearchNewNoteReview/round2/kingsbury/probe.inc \
  --prefix Tests/FocusedSearchNewNoteReview/round2/kingsbury/prefix.h \
  --launches 2

NV_KINGSBURY_DECOMPOSED_TITLE=1 NV_KINGSBURY_LEGACY_TITLE=1 \
python3 Tests/ViewControlsReview/run-probe.py \
  --probe Tests/FocusedSearchNewNoteReview/round2/kingsbury/probe.inc \
  --prefix Tests/FocusedSearchNewNoteReview/round2/kingsbury/prefix.h \
  --launches 2
```

Both commands exit 1 at the same raw-title assertion.
See `decomposed-title.log` and `legacy-decomposed-control.log`.
`Sources/Model/NoteObject.m:982` derives a title from an externally renamed filename;
`updateFromCatalogEntry:` calls that path at line 1586.
The same file also NFC-normalizes titles separately in `_resanitizeContent` at line 1001.
Those paths and `NotationFileManager.m` are unchanged in this PR.
The observed punctuation change therefore cannot be explained by NFC normalization alone.
This is a non-blocking storage observation, not a new Command-N regression.

## Limits and fixture correction

This is a successful-checkpoint and reopen test, not a storage-failure or power-loss test.
It covers the local host filesystem; it does not model external editors or concurrent file replacement.
The legacy control uses that entry point in the current binary, not a separate baseline build.
Its first attempt used pending Fuzzy selection and stopped at a fixture selection assertion.
The final control uses synchronous Exact mode and reaches the same second-launch title failure as Command-N.
The decomposed variants stop at that title failure and do not establish all later source and filename assertions.
No production code changed and no broad desktop suite was rerun for this bounded review.
