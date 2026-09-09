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
