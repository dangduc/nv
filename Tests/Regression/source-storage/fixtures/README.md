# Legacy Simplenote library fixture

`legacy-simplenote.notation` is a 3,681-byte unencrypted local library archive.
The preserved Development app from commit `65e1608ff4e9977ec2d7a09297739152f9cfc935` wrote it before Simplenote support was removed.
Its producer executable was `build/SyntaxFlickerReview/fix.app/Contents/MacOS/nvALT`.

SHA-256 values:

| File | SHA-256 |
| --- | --- |
| Library fixture | `123f0b3dadb57501d031185d666c572fe54688c50cced21ea0a6966b39cf5105` |
| Producer executable | `ee8e9ca27c99d55ff867afabd49e75c12f5548f49ac93dc733f514f477cac365` |

The fixture contains one local source note with fixed UUID, dates, and journal sequence.
Its source includes Unicode, CRLF, a tab, and unsent changes.
It also contains local Markdown syntax, an enabled synthetic account, remote upload metadata, and one remote deletion tombstone.
The account uses `fixture@example.invalid` and contains no password or API key.

The test reads this fixed artifact. It does not regenerate it with the current encoder.
This lets the test detect changes that break the old archive format.
The generator sets account dictionaries directly and never starts a service or accesses account credentials.
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
