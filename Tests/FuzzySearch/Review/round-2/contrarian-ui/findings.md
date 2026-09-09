# Round 2: repaired duplicate-result interactions

No new actionable finding emerged from this bounded review. Both executions passed 71 checks across 12 new scenarios.

The review accepts title matches followed by the complete native fuzzy order. A note can appear in both groups.

Reviewed input: the repaired worktree atop `a611cee399db63eb9edb0958358469c0eda30945`. This revision alone does not identify the repairs. The source records contain exact hashes for the worktree files and extracted methods. Both executions used identical source files, and each file remained unchanged during compilation.

Environment: macOS 26.5.2, build 25F84. Xcode 26.6, build 17F113. All execution used native arm64. No Intel process ran.

## Evidence

| Command | Result | Records |
| --- | --- | --- |
| `python3 Tests/FuzzySearch/Review/round-2/contrarian-ui/run.py --arch arm64` | Pass, 71 checks | `native-results.txt`, `native-source-record.json` |
| `python3 Tests/FuzzySearch/Review/round-2/contrarian-ui/run.py --arch arm64 --sanitize` | Pass, 71 checks. No address or undefined-behavior sanitizer finding. | `sanitize-results.txt`, `sanitize-source-record.json` |

The new probe uses real hidden `NSWindow`, `NSTableView`, and field-editor instances. The runner extracts the repaired table methods and the production `deleteNote:` method. It compiles the complete browser session, search service, query, corpus, and native matcher.

The probe submits edits through the production browser projection. A one-use hook in the model double changes search state during the old title commit. The delete probe captures the actual confirmation block through a temporary `NSAlert` method replacement. It then changes state before it delivers confirmation.

## New cases

| Case | Observed behavior |
| --- | --- |
| Focus change refuses to end the old editor | The old text and target survive. A later retry commits the old title and starts the correct next editor. |
| Old title commit changes title-group order | The requested Beta row moves from 1 to 0. The new editor follows Beta and keeps its target. |
| Old title commit removes its literal-title match | The requested title occurrence resolves to the same note's fuzzy occurrence. The capture remains attached to that note. |
| Old title commit invalidates results | The old title commits. The new editor and its capture remain absent. |
| Old title commit removes the requested note | The second editor remains absent. The old edit still commits. |
| Requested note receives a different object with the same UUID | The guard rejects the replacement object as an inline-edit target. |
| Old commit replaces the browser session and library | The old title commits to its original note. The new editor remains absent, and the replacement library stays unchanged. |
| The old edit target disappears before the transition | Its obsolete value does not reach the model. The second live target receives the new capture. |
| Title-group sort precedes a duplicate-row context menu | Fuzzy primary identity survives the sort. The context menu changes the primary occurrence and sends exactly one change notification. |
| Delete confirmation follows selection and sort changes | Four selected rows produce two captured note targets. One removal call deletes those original notes. |
| Library replacement precedes Delete confirmation | Both libraries remain unchanged, including a replacement library with a reused note UUID. |
| A captured note disappears before Delete confirmation | The action removes only the two surviving targets. Pending results cannot capture another deletion request. |

Selected output:

```text
CASE reorder old_row=1 resolved_row=0
CASE title-removal fallback_row=4
CASE requested-replacement same_uuid=1 new_editor=0
CASE duplicate-context old_title=0 new_title=2 unique_targets=1 context_notifications=1
CASE delayed-delete selected_rows=4 deleted_notes=2 removal_calls=1
ROUND 2 INTERACTION REVIEW PASSED (71 checks)
```

## Scope and limits

The Round 1 finding remains a public-method robustness defect with unproven ordinary app reachability. This review does not expand that claim. The probe forces synchronous callbacks during the overlap to examine the repaired guard. These callbacks exercise the production methods, but they do not establish an ordinary click or keyboard sequence in the complete app.

The model, preferences, and browser delegate are test doubles. The native table, field editor, search engine, browser projection, and deletion block use production behavior. The confirmation sheet itself does not appear. Bulk tag-panel behavior, header visibility, full-app body Undo, and editor attachment remain outside these new executions.

AppKit reported an unavailable `com.apple.hiservices-xpcservice` connection. All native field-editor and deletion assertions still completed.

This review wrote only Round 2 evidence. It did not edit production files or original tests, change Round 1 evidence, or create a commit.
