# Round 1: John Ousterhout-inspired review

This review uses an abstraction and ownership lens. John Ousterhout did not perform or endorse this review.

PR: #8. Baseline: `30c3cf816c80e4ff957223d55f22b36074880ef1`.
Reviewed production changes from `119c45302123c14d02dd0c9b620709bf68e6f086`.

## Finding

### P2: Separate archive verification from pending retention work

Location: `Sources/Storage/NVBackupController.m:291` (also line 283).

An unchanged archive ends the operation before retention runs. After the user lowers retention, automatic checks verify the archive but never apply the new policy. The same path clears a previous retention error without retrying the failed cleanup. A quiet library can therefore retain unwanted snapshots indefinitely and show no remaining error.

The coordinator treats two separate results as one: snapshot integrity and destination maintenance. Keep pending retention work separate from publication. Apply changed policies and retry failed cleanup even when archive bytes are unchanged. Clear a retention error only after that cleanup succeeds. Preserve the existing rule that a quiet library does not need another snapshot.

This is the same issue independently found by the Dan Luu-inspired reviewer. It needs one consolidated fix.

Evidence uses the production coordinator and deterministic store, clock, defaults, and queue fixtures. The store returns a successful publication with an injected `retentionError`. The next automatic check clears that error while the publication count stays at one. Lowering retention also leaves that count at one. The coordinator does not call a separate prune method on this path.

## Restore contract results

No additional actionable restore ownership defect was confirmed in this round.

The new executable extracts the current `restoreBackupArchive:toDirectory:error:` method and runs it with call-count collaborators. It checks composition and nested-folder rejection, preparation failure, replacement failure, original-library resume failure, and successful replacement ordering. It verifies that browser/session commits precede old-library preparation and that successful replacement requests teardown without committing again.

Three negative mutations are rejected: removing preparation, recommitting after preparation, and skipping original-library resume. The existing subordinate teardown harness also passes and rejects its three mutations.

## Commands and results

The retention runner now checks corrected behavior by default. Add `--baseline` to reproduce the historical results below from `30c3cf8`.
The consolidated fix is documented in [the measurement review's fix record](../luu/FIX.md).

From the repository root:

- `python3 Tests/BackupReview/round1/ousterhout/run.py`
  - Passed five retention behavior assertions. This is a baseline bug reproduction, so it expects the incorrect behavior described above.
  - Publication count: one after the injected retention failure; still one after the automatic check and changed retention settings.
- `python3 Tests/BackupReview/round1/ousterhout/run-restore.py`
  - Passed 23 extracted application restore-contract checks.
  - Rejected all three unsafe mutations.
- `python3 Tests/BackupStore/run-teardown.py`
  - Passed four extracted subordinate teardown checks.
  - Rejected all three unsafe mutations.

## Limits

The retention probe executes the production coordinator with a mocked store. It does not measure actual snapshot deletion or disk use. The separate Dan Luu review supplies combined store evidence.

The restore probe executes one extracted production method. Its library, browser, store, and session collaborators record calls; they do not perform application startup, journal I/O, or window updates. The subordinate harness also extracts methods. These results establish call ordering, not complete window and journal integration.

All new binaries ran natively on this Apple Silicon host. No Intel application was launched because the host's copied Intel app stalls before startup. No production source was changed by this review.
