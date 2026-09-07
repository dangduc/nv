# Round 2: Adversarial test skeptic

This is an AI review from a contrarian testing perspective. Reviewed commit `4008592` for PR #1.

## P2: Relaunch coverage does not verify edited note bodies

**Location:** `Tests/MultipleWindowsTests.m:80` and `Tests/MultipleWindowsTests.m:208-218`.

Every note edited by the main fixture is deleted before relaunch. The remaining Beta note is checked by title and count. No assertion checks its restored body. A test-only serialization mutation substitutes each body with the same number of `x` characters. All 47 checks still pass, including successful flush and relaunch.

The production verification path remains active. `NoteObject.m:469` archives the body; `NotationController.m:278-281` compares restored body lengths. `NotationFileManager.m:565-571` rejects failed verification. The same-length substitution passes that guard without bypassing it.

**Requested change:** Keep a note edited through a browser in the relaunch fixture. Assert its exact restored body. Preserve the same-length mutation as a canary for this assertion.

**Command:**

```sh
python3 Tests/ReviewEvidence/round2/test_contrarian/run-canaries.py
```

Run against the matching Development build outside the process sandbox for Rosetta/Cocoa.

| Experiment | Result |
| --- | --- |
| Current suite | 47 assertions, exit 0 |
| Empty archived body control | Exit 1 at “shared library flushes successfully”; 9 mutations |
| Same-length body substitution | 47 assertions, exit 0; 10 mutations |
| Actual browser edit plus exact relaunch-body assertion | 48 assertions, exit 0 |
| Added assertion with same-length substitution | Exit 1 at “relaunch preserves the exact body edited in a browser”; 10 mutations |

The runner exits zero only when all five expected outcomes occur. The empty-body control demonstrates that the existing verification and flush assertion detect length loss. The added fixture types ` persisted edit` in Beta's Cocoa editor and checks `beta only persisted edit` after relaunch.

## Coverage and limits

The existing query, visible-field, and snapback assertions pass in both unmutated runs. This review adds an independent durability canary; it does not repeat query removal.

No current serialization defect was demonstrated. The finding concerns missing semantic body checks in the acceptance suite. Crash recovery, disk-full failures, live sync, and external editor applications were not exercised.

Runtime overrides are guarded by bundle identity, temporary app path, and method signatures. All runs use copied apps, temporary notes, unique preferences domains, and the shared GUI lock. Production source, the shared built app, and historical round-one evidence remain unchanged.
