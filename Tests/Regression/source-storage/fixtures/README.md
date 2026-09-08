# Legacy Simplenote library fixture

`legacy-simplenote.notation` is a 4,233-byte unencrypted local library archive.
The preserved Development app from commit `65e1608ff4e9977ec2d7a09297739152f9cfc935` wrote it before Simplenote support was removed.
Its producer executable was `build/SyntaxFlickerReview/fix.app/Contents/MacOS/nvALT`.

SHA-256 values:

| File | SHA-256 |
| --- | --- |
| Library fixture | `07bc028440a8dfba96f53023f3035141a94c5b1ecd8b6cd23d99eaeb9bf52f4d` |
| Producer executable | `ee8e9ca27c99d55ff867afabd49e75c12f5548f49ac93dc733f514f477cac365` |

The fixture contains one local source note with fixed UUID, dates, and journal sequence.
Its source includes Unicode, CRLF, a tab, and unsent changes.
It also contains local Markdown syntax, an enabled synthetic account, remote upload metadata, and one remote deletion tombstone.
The account uses `fixture@example.invalid` and contains no password or API key.
The account, live note, and tombstone use `SN`, the old app's registered service identifier.
The note and tombstone contain dirty metadata with remote keys, versions, and modification times.

The test reads this fixed artifact. It does not regenerate it with the current encoder.
This lets the test detect changes that break the old archive format.
The generator sets account dictionaries directly and never starts a service or accesses account credentials.
Before and after an archive self-read, it verifies account recognition and the exact live-note and tombstone metadata through the old app.
The regression suite uses test-only archive readers to verify these same fixture preconditions without restoring remote APIs to the application.
The copied-app harness uses disposable notes and a separate preferences domain.

To regenerate from the preserved pre-removal app, run this command from the repository root:

```sh
NV_LEGACY_FIXTURE_DIRECTORY="$PWD/Tests/Regression/source-storage/fixtures" \
python3 Tests/ViewControlsReview/run-probe.py \
  --app build/SyntaxFlickerReview/fix.app \
  --prefix Tests/Regression/source-storage/fixtures/generator-prefix.h \
  --probe Tests/Regression/source-storage/fixtures/generate.inc
```

Archive encoding can include environment-specific display preferences.
If regenerating changes the artifact, inspect the content and update its hash.
Keep the producer version separate from the app under test.
