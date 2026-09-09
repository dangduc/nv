Review of PR #10 found two P2 failures in deferred browser actions.
The review used a concurrency and consistency lens, without an identity claim about Kyle Kingsbury.
The requested source commit was `c7e61cb`, against `a9539cc`.
The recorded runs used `9d468fcc2c87d13d74ccd646036c296d975cc8f1`.
The reviewed production files had no differences between these source commits.

**[P2] Cancel deferred Return when the browser loses key focus**

Location: `Sources/Browser/AppController_Search.m:14–15` and `114–119`.
The missing cancellation is in `Sources/Browser/AppController.m:1866–1868`.

A user presses Return during a pending Fuzzy query, then switches to another browser before the result arrives.
The first browser retains its field editor after it loses key status.
`searchFieldHasFocus` therefore stays true.
`windowDidResignKey:` does not cancel the Return intent.
The completion opens a result or calls `createNoteIfNecessary` for a zero result in the inactive browser.

The executable witness used the query `key-loss-zero` and a corpus with no match.
Before completion, the window was not key, the focus predicate was true, and the Return intent was present.
After completion, the creation counter increased from one to two.
A second trace switched away and back before completion. Its creation counter increased from two to three.
An `isKeyWindow` check at completion alone cannot cancel this second trace.

The native AppKit probe ran the exact production focus predicate with a real `NSWindow` and `NSSearchField`.
It recorded this transition:

```text
APPKIT_FOCUS accepted=1 key_before=1 focus_before=1 key_after=0 focus_after=1 same_editor=1 text_end_delta=0 resign_delta=1
```

The window sent one resignation notification and no field-editing-end notification during this transition.
Thus, the cancellation in `controlTextDidEndEditing:` does not cover key focus loss.
The fix must cancel the Return and autocomplete intents on resignation.
Programmatic Reveal and restoration need separate treatment because they can target background browsers.

**[P2] Preserve all plural Reveal targets after an asynchronous wait**

Location: `Sources/Browser/AppController.m:1723–1729`.
The completion dispatch is at `Sources/Browser/AppController_Search.m:89`.

A key browser requests Reveal for two notes during a pending Fuzzy query.
The query includes one requested note and excludes the other.
The user switches windows before the current result arrives.
The completion calls `notation:revealNotes:`, which calls `cancelOperation:` to clear the query.
That method ignores query changes in a non-key window (`AppController.m:1019`).
Reveal therefore selects only the included note and silently omits the excluded note.

The executable witness queried `copper` and requested `Road map` plus `Other`.
Only `Other` contained `copper`.
The browser was key at the Reveal request and non-key at completion.
After completion, the query remained `copper`, and the selected notes contained only `Other`.

The new asynchronous wait creates this interval between a valid foreground request and a background completion.
`NotationController.m:1123` uses plural Reveal after an import adds multiple notes.
The singular Reveal path already clears an excluded query independently of key status.
The plural path needs the same behavior after the current result establishes exclusion.

**Commands and results**

```sh
python3 Tests/FuzzySearch/Review/round-1/kingsbury/run.py
python3 Tests/FuzzySearch/Review/round-1/kingsbury/run.py --sanitize
python3 Tests/FuzzySearch/Review/round-1/kingsbury/run-appkit.py
```

The native and AddressSanitizer/UndefinedBehaviorSanitizer runs passed 55 assertions each.
Three assertions establish the two failure witnesses. A successful run means those failures remain reproducible.
The AppKit probe exited with zero after it sent events through the application event loop.
The desktop probe required execution outside the sandbox for application activation.
The runs used arm64, macOS 26.5.2 (25F84), and Xcode 26.6 (17F113).

`native-results.json`, `sanitize-results.json`, and `appkit-results.json` contain the output and source identities.
The state records include SHA-256 hashes for each extracted production method.
The fixture also supports `--expect-fixed` to require cancellation and complete Reveal after repairs.
That mode writes separate result files.

**Scope and limits**

The state fixture runs unchanged production methods from `AppController_Search.m`, `AppController.m`, and `AppController_MultipleWindows.m`.
It runs the real browser session, search service, query parser, immutable corpus, and native matcher.
It supplies in-memory model objects and deterministic controls. It records note creation at the controller call boundary.
It does not open a notes library or exercise persistence, rendering, input-method software, or full application event routing.
The AppKit probe separately establishes the real window and field-editor lifecycle for the first finding.
No Intel process ran during this review.

Passing assertions cover these behaviors:

- Literal title rows precede the complete native result in native order, including duplicate UUID occurrences.
- Document actions deduplicate duplicate occurrences, and Return keeps an explicitly selected occurrence.
- Pending results cannot create notes. A current zero result authorizes one creation, and repeat completion cannot repeat it.
- A new query, composition, field-editing-end notification, request invalidation, closure, or library attachment cancels obsolete Return.
- A failed result cannot authorize creation or defer Return.
- Deferred restoration preserves the selected occurrence and source caret. Mode-less state restores as Exact.
- Singular Reveal clears an excluded query in a background browser.

The test leaves service lifecycle and ownership checks to the separate completed review.
It makes no claim about full desktop-suite coverage.
