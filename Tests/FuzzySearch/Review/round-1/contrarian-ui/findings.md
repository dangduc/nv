# Round 1: duplicate-result interaction review

The review accepts both result groups and duplicate notes across those groups. It does not propose deduplication of visible rows.

Reviewed production revision: `c7e61cb`. The workspace later reached `9d468fc` through review-record commits. All four reviewed production files remained identical to `c7e61cb`. `reviewed-inputs.json` records their hashes and comparisons.

Environment: macOS 26.5.2, build 25F84. Xcode 26.6, build 17F113. All executions used native arm64. No Intel process ran.

## Finding candidate: preserve an existing edit before replacing its target

Proposed severity: **P2 robustness defect**. This is **not a confirmed ordinary user-interaction regression**. The public-method failure is reproducible, but an overlapping caller in the current app remains unproven.

Location: `Sources/UI/NotesTableView.m`, lines 1336–1342. Related rejection: `Sources/Browser/NVBrowserSession.m`, lines 46–53.

Trigger: an inline title edit exists on row 0. Before that editor ends, `editColumn:row:withEvent:select:` starts an edit on row 1.

The new code replaces the captured note and row before `NSTableView` finishes the previous editor. AppKit then submits the previous value with row 0. The browser projection sees the row-1 capture and rejects the row-0 value. The title stays unchanged, and the model setter receives no value for the previous edit.

The native probe uses the production `editColumn:` implementation and production browser projection. The superclass is real `NSTableView`, with its real field editor. Model content lives in disposable memory.

Observed output for `c7e61cb`:

```text
INLINE second edit title0=road title1=road zebra editor=road zebra
FAIL: starting an edit on another row must commit the previous title
```

The control replaces only `editColumn:` with its `a9539cc` implementation. All other production methods stay at the reviewed revision. The identical native transition then preserves the title:

```text
INLINE second edit title0=road modified title1=road zebra editor=road zebra
FUZZY BROWSER TESTS PASSED (97 checks)
```

A bounded correction can finish any current editor before it replaces the capture. The new capture must survive the previous editor's completion callback.

Caller limits: the explicit production calls occur in `keyDown:` and `editRowAtColumnWithIdentifier:`. The latter also serves Tab and reverse-Tab transitions under horizontal layout. This app returns `NO` from `browserHorizontalLayout`. Plain Tab committed the title and ended its editor in the native probe. No ordinary click or shortcut sequence established the overlapping transition. The finding therefore supports a defensive regression guard without a claim of routine user text loss.

## Executable evidence

The copied browser harness adds native table interaction checks. The runner extracts production methods at execution time. It compiles the real browser session, search service, query, corpus, and native matcher. Production files and original test files remain unchanged.

| Command | Result | Record |
| --- | --- | --- |
| `python3 Tests/FuzzySearch/Review/round-1/contrarian-ui/run.py --arch arm64` | Pass, 100 checks. Includes an assertion that reproduces the known title-loss behavior. | `native-results.txt` |
| `python3 Tests/FuzzySearch/Review/round-1/contrarian-ui/run.py --arch arm64 --expect-inline-preserved` | Expected exit 1 at the preservation assertion. | `head-preservation-assertion.txt` |
| `python3 Tests/FuzzySearch/Review/round-1/contrarian-ui/run.py --arch arm64 --baseline-inline --expect-inline-preserved` | Pass, 97 checks. | `baseline-results.txt` |
| `python3 Tests/FuzzySearch/Review/round-1/contrarian-ui/run.py --arch arm64 --sanitize` | Pass, 100 checks. No address or undefined-behavior sanitizer finding. | `sanitize-results.txt` |

AppKit reported an unavailable `com.apple.hiservices-xpcservice` connection. The native field editors and assertions still completed. Source records include compilation inputs, hashes, architecture, and the extracted-method hash.

## Passing interaction checks

- Both title and native result groups preserve their required order and shared notes.
- Bulk projections deduplicate UUIDs for legacy table callers and note actions.
- Return edits the primary fuzzy occurrence with both occurrences selected.
- The context menu changes the primary occurrence without changing the selected duplicate rows.
- Shift-arrow expansion and contraction preserve the native active occurrence.
- Row-key restoration preserves occurrence identity across title-group sorting.
- Each browser keeps its own primary occurrence over the same note.
- A captured inline target rejects a commit after the library removes the note.
- A captured inline target accepts its commit after search invalidation.
- Pending results block native selection, Return editing, and context menus.
- Captured bulk tag targets survive selection changes and skip removed notes.
- Library replacement rejects captured bulk tag targets.
- A foreign tag-panel notification does not cancel another browser's tag targets.

## Remaining limits

The native harness substitutes note storage, preferences, table display formatting, and the browser delegate. It uses the production projection for inline commits. It does not exercise full-app editor attachment, body Undo, hidden-list layout, or title/tag header visibility. Static inspection found no additional actionable defect in those paths. The full Intel app workflow remains unexecuted because Intel runtime execution stalls on this host.
