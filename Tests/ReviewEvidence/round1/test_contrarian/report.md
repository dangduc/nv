# Round 1: Adversarial test skeptic

This is an AI review from a contrarian testing perspective. Reviewed commit `30791c5` against `4c6cf45` for PR #1.

## P2: The relaunch suite passes when query restoration is removed

**Location:** `Tests/MultipleWindowsTests.m:78-81` and `Tests/MultipleWindowsTests.m:195-199`.

The final saved fixture uses empty queries. Relaunch checks count, one note selection, and sort, but does not assert either query. Removing the `search` field before every `restoreBrowserWindowState:` call leaves all 44 checks passing. This permits a regression in the advertised per-browser query persistence to escape the required suite.

**Requested change:** Before quitting, save distinct non-empty queries in the two browsers. After relaunch, assert each restored query. Keep a test-only behavior-removal canary to demonstrate that this regression fails the assertion.

**Command:**

```sh
python3 Tests/ReviewEvidence/round1/test_contrarian/run-canaries.py
```

Run with the Development app built into `build/DerivedData`, outside the process sandbox for Rosetta/Cocoa.

| Experiment | Result |
| --- | --- |
| Original suite | 44 assertions, exit 0 |
| Original suite, search restoration removed | 44 assertions, exit 0; mutation invoked 4 times |
| Original suite, reverse-sort restoration removed | Exit 1 at “window state restores selected note and sort” |
| Added distinct-query fixture and assertion | 45 assertions, exit 0 |
| Added assertion, search restoration removed | Exit 1 at “relaunch restores distinct non-empty browser queries” |

The final runner exits 0 only when all five expected outcomes occur. The reverse-sort control confirms that injection runs and that an existing restoration assertion catches a different removed behavior.

## Coverage and limits

The mutation uses a guarded method swizzle in a test dylib. It runs only inside a copied app with a unique preferences domain and temporary notes. It checks the method signatures and deletes only the generated preferences domain. The shared GUI lock serializes the runs. No production sources or the shared app were changed.

This finding concerns test coverage. The added query assertion passes against the current implementation; no current query-restoration defect was demonstrated. The existing suite also detects removed sort restoration. This review did not exercise live sync, crash recovery, or external editor applications.
