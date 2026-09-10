# Round 3: refresh ownership and metadata ordering

Reviewed PR #24 at `d93f93521beb4cd9f6e7d2ba77000eb2bcb41bd6`, against `8dde5e8`.
Production changes match `5eda58b`.
Perspective: design and state ownership, inspired by John Ousterhout's work.
This review does not claim his authorship or endorsement.

No actionable findings in this review slice. No production fix is proposed.

The coordinator owns committed search snapshots and shared editing sessions.
The browser owns its source-edit guard and its list projection.
Body notifications refresh editor state; metadata notifications update selected headers through separate methods.
The executed interleavings preserve those responsibilities without losing a header or list update.

Command:

```sh
python3 Tests/TypingReview/round3/ousterhout/run.py
```

Actual result: exit 0; **21 checks passed across four new scenarios**, plus cache identity checks.
See [output.txt](output.txt) and [results.json](results.json).
Compiled objects, extracted methods, the executable, and the compiler log are under `build/TypingReview/round3/ousterhout/`.

The runner compiles the production `NVBrowserSession` and native search service in full.
It extracts these production methods without logic changes:

- Coordinator snapshot construction, change classification, invalidation, scheduling, editor broadcasts, metadata updates, external reload, and editing-session lookup.
- Browser source-change handling, peer editor refresh, and title-update handling.
- UUID conversion used by the editing-session cache.

The new cases use three browser sessions: two select the edited note; one selects another note.

1. A body notification runs inside the originating source commit, followed by a tag change.
   Only the originating duplicate editor callback is suppressed.
   Both selected headers update while the source guard is set.
   Metadata cancels pending body rows, and all browsers publish once.
2. A title change is followed by two body changes before the scheduled refresh.
   Selected headers update, and each list publishes once with the final committed snapshot.
   Repeating the unchanged snapshot creates no additional work.
3. After metadata work completes, a body-only update preserves current empty-query commands.
   It redraws one row in every browser and produces no full list publication.
4. A controlled commit exception exercises the actual source handler's `finally` block.
   The guard clears, and a later editor broadcast reaches that browser.
   Explicit external contents refresh reuses the cached session and updates both selected lists.

The cache checks confirm that the same UUID shares a session, another note receives a separate session, and nil allocates none.

Source inspection also traced `NotationController` metadata hooks and the editing session's body-only broadcast.
Those call sites explain why removing header updates from `refreshEditorForNote:` does not remove metadata header delivery.

Limits: note models, views, preferences, and editing-session internals are doubles.
The commit double injects deterministic callbacks; it does not execute persistence, Undo, composition, or source analysis.
The metadata helper follows the inspected model-hook order but does not execute production metadata setters.
The external session reload is counted; its storage reconciliation is outside this probe.
The fixture does not instantiate desktop windows or establish rendering, timing, or full application behavior.
This review changed no production files, used no GUI, created no commits, and posted no comments.
