# Round 3: delayed tag actions and same-note occurrences

No actionable introduced finding emerged from this bounded review.
The review preserves both result groups, including duplicate notes across the groups.

The native run passed **89 checks across eight new scenarios**.
The sanitizer run passed the same checks, without an address or undefined-behavior sanitizer report.
All three negative controls failed their intended assertions.

## Evidence

```sh
python3 Tests/FuzzySearch/Review/round-3/contrarian-ui/run.py --negative-controls
python3 Tests/FuzzySearch/Review/round-3/contrarian-ui/run.py --sanitize
```

The runs used native arm64 on macOS 26.5.2, build 25F84, with Xcode 26.6, build 17F113.
No Intel process ran. The completed executions required desktop access.

The runner copies implementation inputs before compilation.
It also copies the relevant search headers, browser header, tag-manager header, matcher data, and English tag-panel nib source.
The source records identify these inputs and the extracted method bodies with SHA-256 hashes.
Concurrent service work can differ from the recorded HEAD, so the input hashes identify the reviewed worktree source.

The fixture compiles the complete browser session, search service, query, corpus, native matcher, and `TagEditingManager` implementation.
It loads the actual English tag-panel nib from a disposable application bundle.
The production `tagNote:` method selects the single-note path or creates the native bulk panel.
Extracted production methods capture UUIDs, resolve delayed targets, apply tags, cancel panels, and process occurrence changes.

The fixture supplies three notes with both title and fuzzy occurrences.
Storage, preferences, preview formatting, and some browser callbacks use test doubles.
No notes directory opens.

## New scenarios

| Interaction | Observed result |
| --- | --- |
| Select both occurrences of one note, then invoke Tags | The action selects the single-note header control. No bulk panel opens. |
| Select four rows for two notes, then change selection, sort, and search state before commit | The native panel captures two UUIDs. The delayed action writes those notes once each and leaves the later selection unchanged. |
| Remove one captured note before commit | The action skips that UUID and writes the surviving captured note once. |
| Replace a captured object with another object that has the same UUID in the same library | The action resolves the current object. The removed object stays unchanged. This matches the required UUID identity for note actions. |
| Replace the active library with one that reuses a captured UUID | The action writes neither library and clears its panel and capture. |
| Open a second bulk action, then deliver the old panel's release notification | The old notification preserves the second capture. The next commit changes only the second target set. |
| Deliver the production tag-panel focus-loss callback, then invoke a late commit | The notification clears the capture. The late action performs no writes. |
| Change primary occurrence between title and fuzzy rows while both rows represent the open note | The browser updates its row context and requests new highlights. It preserves the note, text storage, layout attachment, caret, and existing Undo entry. |

Selected output:

```text
CASE delayed-tags captured_rows=4 unique_targets=2 writes=2 later_selection_untouched=1
CASE library-replacement reused_uuid=1 total_writes=0
CASE panel-replacement old_notification_ignored=1 current_writes=2
CASE same-note-occurrence rows=2 editor_attachments=0 undo_and_redo_preserved=1 highlights=4
ROUND 3 INTERACTION REVIEW PASSED (89 checks across 8 scenarios)
```

The same-note case also executes one Undo and one Redo after both occurrence changes.
Each operation restores the expected source string.

## Negative controls

| Deliberate mutation in copied inputs | Detected consequence |
| --- | --- |
| Remove UUID deduplication from `NVBrowserSession.notesAtIndexes:` | Two occurrences of one note enter the bulk-panel path instead of the single-note path. |
| Remove the active-library guard from `pendingMultiTagNotes` | A delayed action mutates the old library after replacement. |
| Force the new-note branch in `displayContentsForNoteAtIndex:` | A primary-only occurrence change enters editor attachment. |

The runner restores each copied input after its control.
It rebuilds the normal fixture after all controls.
No production file changes.

## Scope and limits

The new evidence extends the earlier direct target-capture checks through the actual Tags action and native panel initialization.
The header control records `selectText:` instead of asserting real keyboard focus.
Selection, deletion, and library changes occur programmatically before the delayed commit.
These transitions do not establish a complete physical mouse or keyboard workflow.

The panel uses its production nib, bindings, properties, and lifecycle methods.
The focus-loss case calls `windowDidResignKey:` explicitly, then exercises its real notification and browser cancellation path.
It does not establish native focus-loss notification timing.

The same-note case uses a real `NSTextStorage`, layout manager, text view, and `NSUndoManager`.
A fixture edit registers the Undo entry before the occurrence changes.
The extracted display path supplies selection behavior, while attachment and highlight callbacks record attempted calls.
The fixture does not compile the full editing session or exercise asynchronous highlight installation.
This result supports preservation at the browser display boundary, not a full-app Undo guarantee.

The compiler support paths still provide unrelated project declarations.
The complete application, browser nibs, file persistence, and Intel desktop workflows remain outside this execution.
The existing Intel startup stall remains unresolved.

Records are `native-results.txt`, `sanitize-results.txt`, and their source-record JSON files beside this report.
Copied sources, the native bundle, compile logs, and mutation logs remain under `build/FuzzySearchContrarianUIRound3/`.
