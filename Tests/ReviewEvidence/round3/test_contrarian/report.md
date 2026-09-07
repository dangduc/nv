# Round 3: Adversarial test skeptic

This is an AI review from a contrarian testing perspective. Reviewed commit `3502c7c` for PR #1.

## Result

No new actionable finding from these probes. The maintained editing and selection suites reject independent removal of the behavior they claim to cover.

**Command:**

```sh
python3 Tests/ReviewEvidence/round3/test_contrarian/run-canaries.py
```

Run against the matching Development build outside the process sandbox for Rosetta/Cocoa.

| Experiment | Result |
| --- | --- |
| Editing suite baseline | 40 assertions, exit 0 |
| Skip history finalization | Exit 1 after 11 passes; 3 mutation invocations |
| Selection suite baseline | 17 assertions, exit 0 |
| Apply the whole text snapshot | Exit 1 after 3 passes; 1 mutation invocation |

The runner exits zero only when both baselines pass and both mutations fail their intended acceptance assertions.

## History finalization canary

The override replaces `NVNoteEditingSession.m:100-109` with a no-op. Ordinary undo and redo still pass their controls. Undo during another browser's composition then fails at `Tests/Regression/editing/probes.m:105`: “undo preserves the deferred external update and removes only the local composition.”

This failure checks the resulting note body. It does not rely on the presence of a particular method call. The current implementation completes marked text and commits pending changes before invoking history at `NVNoteEditingSession.m:119-125`.

## Selection preservation canary

The override replaces `applyContents:` at `NVNoteEditingSession.m:47-67` with `setAttributedString:` on the shared storage. An ordinary suffix edit still preserves the peer selection. Undo then fails at `Tests/Regression/selections/probes.m:98`: “undo preserves peer selection before the edited suffix.”

The current implementation applies the changed character range separately from attribute updates. The canary confirms that whole-text replacement cannot silently replace this behavior while the selection suite stays green.

## Scope and limits

These are new runtime mutations against the existing acceptance harnesses. The harness assertions were not rewritten for this review. The prior query and archived-body canaries were not reused as sole evidence.

Each case uses a copied app, temporary notes, a unique preferences domain, and the shared GUI lock. Overrides require the disposable bundle identity and path, and matching Objective-C method signatures. Production files and the shared built app remain unchanged.

This review does not establish complete selection coverage. In particular, simultaneous changes around an unchanged selection and rendered-preview lifetime were under separate review. No claim about those paths follows from these results.
