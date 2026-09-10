# Round 1 — Kyle Kingsbury-inspired state and interleaving review

This is an agent review using a state and interleaving perspective, not a review by Kyle Kingsbury.

No actionable regression found in the tested candidate. The new library-switch crash is preexisting. The candidate methods were frozen for the native probe; `source-hashes-start.txt` and `source-hashes-end.txt` match. Subsequent changes belong to the next review round.

## Executable evidence

`python3 -B Tests/SourceBackspaceReview/round1/kingsbury/run-interleavings.py --negative-controls`

The runner extracts the production invalidation observer and editor cleanup/publication methods. It links them to native `NSTextStorage` and two separate layout managers. AddressSanitizer and UndefinedBehaviorSanitizer were enabled. All 13 checks passed:

- Both owners advance their callback generation during the same character notification.
- A switches notes before cleanup runs; its fresh backgrounds survive while B cleans its original storage.
- Later B edits leave A's generation unchanged after detachment.
- Fresh snapshot publication cancels queued cleanup.
- Full source replacement cleans the new range safely.
- Cancellation permits both owners to release.

The two negative controls failed at the intended assertions. Removing cancellation erased the new note's backgrounds. Removing the generation increment broke the immediate fence in both owners. Logs and JSON preserve the output.

This adapter does not instantiate full browser windows, invoke real marked-text composition, or execute the application's note-switch method. It applies the production detach/cancel ordering to native TextKit objects. Full-app shared editing, composition, Undo, window closure, and restoration are covered by the window suite described below.

## Attribution of the newly reachable suite failure

The root's candidate run passed all 35 main-window checks, including shared Undo, marked-text/external-update interaction, source detachment, and owner closure. During relaunch it then crashed after 11 checks, immediately after opening a replacement library. The stack entered `AppController.m:1820`, `NVBrowserSession.m:456`, and `AppController_MultipleWindows.m:62`.

I reproduced the same failure in the previously built app from `OrgPreviewWorktree`. The test-only adapter replaces only `searchSourceStorageWillProcessEditing:`: it retains the generation increment and omits the premature highlight removal. This bypasses the known old Undo exception so the old app can reach the later assertions. It does not patch library attachment or table access.

Reproduce from this worktree:

```sh
python3 -B Tests/SourceBackspaceReview/round1/kingsbury/run-windows-comparison.py \
  --app /Users/duc/dev/nv/build/OrgPreviewWorktree/build/DerivedData/Build/Products/Development/nvALT.app \
  --label baseline --suppress-early-cleanup
```

The baseline passed 35 main checks, then received SIGSEGV after 11 relaunch checks. Its crash stack matches the candidate; the old line number is `AppController.m:1818` because the candidate adds two lines above it. Both stacks point to the same `viewingLocation` access. The unchanged attachment path calls `setSearchService:` before replacing the notes table's old data source. This is consistent with a stale table/data-source state during the synchronous refresh callback. I did not patch or fully diagnose that independent defect.

Therefore the full window suite is **not passing**. The backspace fix permits it to reach an existing later failure. This review does not propose changing unrelated library-switch behavior in this PR.

The tests ran on macOS 26.5.2. They do not establish the exact crash behavior on the user's macOS 13.7.8 system.
