# Snapshot diff invariants

Run on macOS with Xcode:

```sh
python3 Tests/Regression/snapshot-diff/run.py
```

The runner extracts `NVChangedRange`, `NVSnapshotEdit`, and `NVSnapshotEdits` from the current production source. It compiles that code with Foundation. It opens no app windows or notes libraries.

The probe checks 36,136 source/target pairs:

- All 16,129 pairs of binary strings through length six.
- 20,000 deterministic random UTF-16 pairs, seed `0x534E4150`, through length 80. The alphabet includes combining characters, NUL, and surrogate code units.
- Four explicit emoji, accent-normalization, Vietnamese, and separated-edit cases.
- Three inputs that exceed the edit-distance, length-imbalance, or work bounds.

Each generated hunk must be in bounds and in reverse nonoverlapping order. Applying the hunks must reproduce every target UTF-16 code unit. Small nonempty changes must produce hunks, so unconditional coarse fallback cannot pass. A fallback uses the same outer-range replacement as the production caller.

Instrumentation counts character accesses and requested trace-buffer bytes without changing the helper body. The work-limit fixture contains 1,000,003 UTF-16 units and falls back after 1,999,990 character reads. The largest trace allocation is 2,117,680 bytes; each call releases it. The runner also enforces a 45-second process timeout and checks that the helper source stayed unchanged during execution.

Final validation passed all 36,136 cases for helper SHA-256 `fb895681a945655cc35cf251e77530f93b66ff1b1ecd69cb02a6c5ddb9a50b70`. This validates text reconstruction and the observed allocation/work bounds. Cocoa selection behavior and attributed-text application have separate integration tests.
