# Automatic backup PR review

PR: https://github.com/fastducduc/nv/pull/8

Each round uses six independent review lenses inspired by John Ousterhout,
Dan Luu, Linus Torvalds, Kyle Kingsbury, and two contrarian perspectives.
These are agent reviews, not statements from those people.

Each reviewer writes and runs an executable probe. Reports identify the code
version, commands, findings, and limits of the evidence. Review probes use
disposable data. They do not access personal notes.

| Round | Production baseline | Status |
| --- | --- | --- |
| 1 | `30c3cf816c80e4ff957223d55f22b36074880ef1` | Six reviews posted; three unique findings |
| 2 | `a89f8351646f824f51ed6ea80b94f724f37d0303` | Six reviews posted; five findings |
| 3 | `8ebbcb511415958f700ca54e4216e6447464d284` | Six reviews posted; no new actionable findings |

All 18 reviews are complete. Delegated agents corrected the eight distinct
findings from rounds 1 and 2. Round 3 added executable checks of the corrected
code and found no new actionable issue within its documented scope.

The host's Intel application startup stall prevents full desktop validation.
Native probes can test production methods or components, with the dependencies
described in each report. They do not establish full application integration.
See [the validation record](../BackupValidation.md).

Run current native review regressions from the repository root:

```sh
python3 Tests/BackupReview/run.py
```

Use `--round 1`, `--round 2`, or `--round 3` to select one round.
Logs go to `build/BackupReview/validation/`.
Reports record their original reviewed revisions. Correction records explain
the regression modes and any explicit options for reproducing earlier behavior.

## Posted reviews

| Round | Lens | PR comment | Evidence |
| --- | --- | --- | --- |
| 1 | Ousterhout | [Review](https://github.com/fastducduc/nv/pull/8#issuecomment-5593766509) | [Report](round1/ousterhout/REPORT.md) |
| 1 | Torvalds | [Review](https://github.com/fastducduc/nv/pull/8#issuecomment-5593771907) | [Report](round1/torvalds/REPORT.md) |
| 1 | Luu | [Review](https://github.com/fastducduc/nv/pull/8#issuecomment-5593782355) | [Report](round1/luu/REPORT.md) |
| 1 | Contrarian data | [Review](https://github.com/fastducduc/nv/pull/8#issuecomment-5593806660) | [Report](round1/contrarian_data/REPORT.md) |
| 1 | Kingsbury | [Review](https://github.com/fastducduc/nv/pull/8#issuecomment-5593809462) | [Report](round1/kingsbury/REPORT.md) |
| 1 | Contrarian workflow | [Review](https://github.com/fastducduc/nv/pull/8#issuecomment-5593824056) | [Report](round1/contrarian_workflow/REPORT.md) |
| 2 | Ousterhout | [Review](https://github.com/fastducduc/nv/pull/8#issuecomment-5593991020) | [Report](round2/ousterhout/REPORT.md) |
| 2 | Torvalds | [Review](https://github.com/fastducduc/nv/pull/8#issuecomment-5593991502) | [Report](round2/torvalds/REPORT.md) |
| 2 | Luu | [Review](https://github.com/fastducduc/nv/pull/8#issuecomment-5594036293) | [Report](round2/luu/REPORT.md) |
| 2 | Kingsbury | [Review](https://github.com/fastducduc/nv/pull/8#issuecomment-5594078283) | [Report](round2/kingsbury/REPORT.md) |
| 2 | Contrarian data | [Review](https://github.com/fastducduc/nv/pull/8#issuecomment-5594078891) | [Report](round2/contrarian_data/REPORT.md) |
| 2 | Contrarian workflow | [Review](https://github.com/fastducduc/nv/pull/8#issuecomment-5594089742) | [Report](round2/contrarian_workflow/REPORT.md) |
| 3 | Luu | [Review](https://github.com/fastducduc/nv/pull/8#issuecomment-5595243181) | [Report](round3/luu/REPORT.md) |
| 3 | Torvalds | [Review](https://github.com/fastducduc/nv/pull/8#issuecomment-5595243650) | [Report](round3/torvalds/REPORT.md) |
| 3 | Ousterhout | [Review](https://github.com/fastducduc/nv/pull/8#issuecomment-5595269663) | [Report](round3/ousterhout/REPORT.md) |
| 3 | Kingsbury | [Review](https://github.com/fastducduc/nv/pull/8#issuecomment-5595297045) | [Report](round3/kingsbury/REPORT.md) |
| 3 | Contrarian data | [Review](https://github.com/fastducduc/nv/pull/8#issuecomment-5595333958) | [Report](round3/contrarian_data/REPORT.md) |
| 3 | Contrarian workflow | [Review](https://github.com/fastducduc/nv/pull/8#issuecomment-5595355109) | [Report](round3/contrarian_workflow/REPORT.md) |

## Findings and corrections

| Finding | Severity | Correction |
| --- | --- | --- |
| Rollback can recover a competing journal | P1 | `89ef4fe`: [exclusive rollback and regression](round1/kingsbury/FIX.md) |
| Unchanged snapshots skip retention and hide cleanup errors | P2 | `a89f835`: [maintenance and retry](round1/luu/FIX.md) |
| A backup discards active numeric preference edits | P2 | `34c3e4a`: [draft preservation](round1/contrarian_workflow/FIX.md) |
| Closing Preferences leaves a numeric draft unsaved | P2 | `dae119b`: [close contract](round2/ousterhout/FIX.md) |
| Plaintext deletion trusts another library's owner record | P2 | `cf4aa78`: [identity-bound deletion](round2/torvalds/FIX.md) |
| A short interval reduces the failure retry delay | P3 | `cf4aa78`: [intentional retry delay](round2/torvalds/FIX.md) |
| An obsolete decode replaces the current status | P3 | `cf4aa78`: [context isolation](round2/torvalds/FIX.md) |
| Failed rollback returns to editing without a journal | P1 | `f7b938e`: [modal recovery and external-editor preflight](round2/kingsbury/FIX.md) |
