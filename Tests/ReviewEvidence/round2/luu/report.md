# Round 2: empirical search review

AI review perspective inspired by Dan Luu; not a statement by Dan Luu. PR #1 head: `4008592`; feature base: `4c6cf45`; prior review head: `30791c5`.

## Result

No new actionable finding reproduced in this scope. The Round 1 zero-result refinement finding remains fixed. This round validates the candidate-cache fix delegated to this reviewer after Round 1.

## New executable evidence

```sh
python3 Tests/ReviewEvidence/round2/luu/run.py
python3 Tests/Regression/search/run.py
```

The new probe compiles production `NVBrowserSession.m` with in-memory model doubles. It uses a deterministic 4,000-step trace, seed `0xD4A1C002`, and 77 queries. After every step, both cached browsers are compared with fresh searches, including row order and selected-row pinning.

Observed result: **8,002 checks passed**, comprising 8,000 differential comparisons and two zero-access assertions. The existing regression suite separately passed **347 checks**.

| Trace operation | Executions |
| --- | ---: |
| Query changes | 893 |
| Body edits | 400 |
| Title changes | 450 |
| Label changes | 456 |
| Note additions | 450 |
| Note deletions | 485 |
| Sort reversals | 437 |
| Selection and pinned-row refresh | 429 |

Queries include quoted phrases, colon separators, case changes, composed/decomposed accents, German sharp s, Greek sigma variants, Turkish dotted I, Vietnamese text, and emoji. Every seventeenth mutation tests a search before a deferred UI refresh can run.

## Code paths assessed

- `NVBrowserSession.m:47-60`: parsed-term refinement retained the same matches as fresh searches in this trace.
- `NVBrowserSession.m:139-175`: edits, additions, deletions, sorting, and pinned rows retained matching membership and order. Deferred refresh invalidation prevented candidate reuse after mutations.
- Following the trace, extending an empty result examined **zero note contents** and requested **zero library snapshots** in each browser. Round 1 measured full-library access at `30791c5`; the head retains the intended change from that snapshot.

## Limits

This is a bounded source-level review on macOS 13.7.8, arm64, Apple clang 15.0.0. It does not exercise Cocoa event routing or live synchronization. `NVApplicationController.m:205-226` still requests full browser refreshes after edits; this round did not measure end-to-end editing latency or establish a separate finding about that path. No production files, shared app builds, or Git state were modified.
