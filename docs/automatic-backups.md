# Automatic backups

nvALT creates backups while the application is open. The default interval is 15 minutes, and unchanged libraries do not create duplicate automatic snapshots.
The first backup follows library startup. Backups continue with all note windows closed until the application quits.

Preferences > Backups contains these controls:

- Enable or disable automatic backups.
- Select the interval and destination folder.
- Set recent, daily, and weekly retention and the storage target.
- View the last successful backup, the next check, storage use, and errors.
- Create a backup immediately, show the backup folder, or restore a backup.

The default destination is `~/Library/Application Support/nvALT/Backups/<library UUID>/`.
The default history retains 96 recent snapshots, 30 daily snapshots, and 12 weekly snapshots, with overlapping groups stored once.
Daily and weekly groups use UTC boundaries. The default storage target is 2 GiB.
The storage target takes priority over older history, but at least three complete snapshots remain.
If these snapshots exceed the target, the status shows the excess.

A snapshot contains committed notes, tags, dates, original source bytes, encoding, and local syntax metadata.
Unfinished text composition and metadata edits enter a later snapshot after their normal commit.
Linked files outside the note model, Undo history, and browser layouts are outside the backup format.
The current format supports archive files through 512 MiB.

Encrypted note data stays encrypted. Some library settings remain readable.
Older encrypted snapshots can require the password that was active at their capture date.
Enabling encryption leaves older unencrypted snapshots unchanged.
The separate deletion action deletes recognized unencrypted snapshots after confirmation. Damaged or unrecognized files remain available for manual review.

## Restore a backup

1. Open Preferences > Backups.
2. Select Restore Backup.
3. Select a complete `.nvbackup` snapshot folder.
4. If the backup is encrypted, enter its original password.
5. Select a new, empty folder outside the active notes folder.

nvALT checks the archive before it switches libraries. The restored library opens in database storage.
The original library remains in its original folder. A restore failure leaves the original library selected.
If that library cannot resume saving, nvALT pauses editing and shows Retry and Quit.
Close any other copy of nvALT, then select Retry. You can also quit and reopen nvALT.
If a note needs an encoding conversion, complete that conversion before switching libraries.
Close active external-editor sessions before restoring. Their temporary files remain intact when this check blocks a restore.
You can select separate text-file storage for the restored library through the existing Notes preferences.

Automatic backups resume after launch or wake. Missed intervals produce one current snapshot, rather than copies for each interval.
If a selected backup volume is unavailable, nvALT shows an error and retries without changing destinations.
A backup on the same disk does not protect against disk failure.
