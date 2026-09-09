# Backup preferences checks

Run from an active macOS desktop session:

```sh
python3 Tests/BackupPreferences/run.py
```

The test builds the production Backups pane with an in-memory coordinator.
It does not open a notes library or change application preferences.
It checks settings changes, numeric input, exact storage-target round trips, and action routing.
It also checks that a pending field edit cannot change a newly opened library's settings.
Controls that change backups must be disabled while the coordinator is busy.
Long status messages must scroll so the final error remains accessible.

The test renders the pane to `build/BackupPreferences/pane.png` for visual inspection.
This test does not validate backup scheduling, archive contents, or filesystem writes.

For native Preferences window-close checks, run:

```sh
python3 Tests/BackupReview/round2/ousterhout/run-pane.py --negative-mutations
```

This probe checks valid and invalid drafts during idle and busy states.
It also checks hidden drafts, correction, and a library switch before a deferred save.
It uses the production pane and extracted window-close delegates with native windows.
Its coordinator and pane-switch collaborators are test doubles. Error presentation records calls without a modal dialog.
