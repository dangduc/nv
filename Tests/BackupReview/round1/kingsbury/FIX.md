# Round 1 rollback fix

Addresses [the P1 review comment](https://github.com/fastducduc/nv/pull/8#issuecomment-5593809462).

`initializeJournaling` now refuses recovery when `backupRestorePrepared` is set, as it already did for replacement initialization.
The original library has already checkpointed its notes and removed its journal at this point.
An occupied pathname must remain untouched.

On collision, rollback returns a journal error, retains its prepared state, and does not restart monitoring.
The application coordinator already passes this error to backup status.
Calling the rollback method again preserves the collision. After the pathname becomes available, that same library can resume.
This change does not add automatic retries or a new UI action.

Validation:

```sh
python3 Tests/BackupReview/round1/kingsbury/run.py
python3 Tests/BackupReview/round1/kingsbury/run.py --check-baseline-mutation
```

The corrected regression passed 17 assertions covering replacement refusal, rollback refusal, error contents, journal preservation, repeated failure, successful retry, and idempotence.
The optional mutation check then removed the guard in memory. The regression rejected that mutation at the failed-rollback assertion.
A separate reproduction mode passed 10 assertions confirming the original foreign-record processing and journal-unlink behavior.

The test executes extracted production methods with real temporary-file creation, unlinking, and descriptor checks.
WAL decoding, encryption, monitoring, checkpoint storage, and UI services remain stubs.
No shipping OpenSSL or full-application validation is claimed.
