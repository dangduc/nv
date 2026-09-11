# Post-fix application validation

The complete application checks passed at commit `9a6903779c36d99fe651bb9ab1f42110d094d215`.
No actionable findings emerged from this rerun.
The frozen `47d18f4` results and output remain unchanged.

Command:

```sh
python3 -B Tests/DevelopmentBuildReview/round3/ousterhout/run.py --commit 9a69037 --output Tests/DevelopmentBuildReview/round3/ousterhout/post-fix
```

All 252 assertions passed in the rebuilt Development and Release applications.
Each application published and decoded default, first manual custom, and first automatic custom backups.
The development namespace was absent before each first custom backup.
Both applications retained the custom bookmark and decoded the same automatic snapshot after relaunch.

`results.json` records the full commit, executable hashes, snapshot paths, and four process reports.
`output/` contains the application logs and window images.
The shared GUI lock covered the run and is now released.
The runner removed all disposable application copies, notes, backup packages, and generated preferences domains.

The case set and limits match the frozen round-three review.
The fixture applies a native bookmark directly to the real coordinator's settings and calls the automatic due-check entry point.
It does not present the folder picker or wait for the timer.
This rerun adds no substitution or retention cases.
No production files changed during this validation.
