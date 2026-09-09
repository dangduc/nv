# Fuzzy search in nv

Implementation design, updated September 9, 2026. The application now implements this search workflow; validation and review continue.
The application baseline is `a9539cca76e260546310caa4918d018f802b064b`.
The dependency is [`fzf-native` main at `4b9236e`](https://github.com/dangduc/fzf-native/tree/4b9236e8cd1e9f9f3aaf5f2ebf83f1fc5995d38d), downloaded for the prototype.
The [fzfa audit](fzfa-async-search-audit.md) supplies the request, cancellation, and publication design.

The recommendation is Fuzzy search in the existing notes search bar, with Exact available from its search menu.
New browser sessions default to Fuzzy. Older mode-less state retains Exact.
Saved searches and window states without a mode will retain Exact behavior.
Each browser will keep its own query, mode, selection, and highlights over the shared notes library.

For Fuzzy queries with terms, nv will show literal title matches first, followed by the full result list from `fzf-native`.
The fuzzy group will preserve native order. A note that matches both groups will appear in both.
The engine will search one complete candidate per note: `title + "\n" + tags + "\n" + source`.
Title priority will come from group placement. The application will not change native scores or sort the fuzzy group again.
The notes list will remain above the editable source or read-only viewer.

**What the prototype establishes**

The [standalone prototype](../Prototypes/FuzzySearch/README.md) already contains a C bridge and an extracted native scorer and sorter.
The application and prototype now share the promoted C code and its tests.
Its Swift interface remains an experiment, separate from the Objective-C application.

| Evidence from September 9 | Meaning for integration |
| --- | --- |
| Native and sanitizer suites each passed 14,992 checks. | Complete result order matches an independently extracted upstream reference across the covered fixtures. |
| Desktop smoke passed supersession, temporary edits, stale-row protection, corpus replacement, and zero-result cases. | The basic background-search interaction works in the standalone app. |
| `qzr` returned five sample notes in Fuzzy mode and one in Exact terms mode. | Complete-note fuzzy matches can span distant characters and lines. |
| One warm generated-corpus query took 17.5 ms for 1,000 notes and 164.9 ms for 10,000 notes. | These arm64 observations do not establish Intel performance or production latency percentiles. |

The prototype accepts native fzf operators. Its Exact terms control is not nv's existing Exact search.
It rebuilds the prepared corpus after edits and uses one worker.
It does not exercise production creation, bookmarks, restoration, library switching, or shared editing.
It also does not exercise title-first grouping or multiple result rows for the same note.
The production suite extends allocation injection into parser, scorer, map, positions, and slab paths.
See [provenance and test scope](../Sources/Search/ORIGIN.md) for covered and excluded allocation paths.
The [test guide](../Tests/FuzzySearch/README.md) distinguishes native checks from pending desktop validation.

**Search behavior**

Fuzzy search matches query characters in order, with gaps. For example, `mtg` can match `meeting`.
It does not provide spelling correction or semantic search.
The first version searches titles, tags, and complete committed source text.
Rendered previews, linked files, and future binary attachments remain outside the corpus.

| Control or input | Proposed behavior |
| --- | --- |
| Search menu | Checked, single-choice Fuzzy and Exact items. The placeholder identifies the active mode. |
| Unquoted terms | Spaces, tabs, newlines, and colons separate terms, as today. Every term must match the same note. |
| Title matches | Every parsed term or phrase must appear contiguously in the title, using the existing case-insensitive Cocoa comparison. |
| Fuzzy terms | Each unquoted term uses native fuzzy matching over the complete candidate. Matches can cross lines and field separators. |
| Double-quoted phrases | Each phrase requires contiguous matching within the candidate. An unfinished quote remains an exact phrase. |
| Punctuation | Apostrophes, `!`, `^`, `$`, and `\|` remain literal. This release does not expose native fzf operators. |
| Case and accents | Fuzzy ignores case and preserves accents. NFC normalization makes canonically equivalent Unicode text match. |
| Exact mode | Preserve existing Cocoa substring matching within individual fields, query parsing, autocomplete, and column order. |
| No parsed terms | Show all notes immediately in the configured column order. This includes empty text and separator-only input. |
| Return in Fuzzy mode | Open the selected result, or the first displayed result. Create from the query only after both groups complete with zero matches. |
| Explicit New Note | Remain available regardless of matches or pending work. It does not infer permission to create from the result count. |

With no parsed terms, Return will retain the existing create-or-focus behavior immediately.
It will focus the open note, or create a note using the field text.
An empty field will supply the existing “Untitled Note” title.
The Create-from-search button will require a current, completed zero-match result and use the same request check as Return.

Fuzzy mode uses the engine's case-insensitive character matching, not full Unicode case folding.
For example, it does not promise that `strasse` matches `Straße`.
Quoted phrases retain the query's phrase syntax but use native comparison in Fuzzy mode.
Exact mode retains its current Cocoa comparison behavior.

The current literal filter searches titles, tags, and bodies. Its separate autocomplete path matches title prefixes and prefers the shortest title.
The requested first group will reuse the literal parser and comparison with its scope restricted to titles.
For example, `road` matches the title “Road map” in that group. Body-only and tag-only matches cannot enter it.
The separate Exact mode will retain its existing behavior.

The combined result will contain two ordered groups:

1. Literal title matches in the configured column order, with UUID order for otherwise equal entries.
2. Every result returned by `fzf-native`, in that exact order, including notes already present in the title group.

Each note can supply one row to each group in the first version.
Group labels will distinguish title matches from fuzzy matches, including for accessibility. Labels will not act as note rows.
Both groups will use the same committed corpus and query.
Cocoa and native Unicode comparisons can differ, so a title match will not require membership in the fuzzy group.

The corpus will supply candidates in stable UUID byte order.
Fuzzy ties will therefore have a reproducible producer order, independent of column settings.
The native default scheme, score clamping, length saturation, and greedy fallback will remain intact.
Every matching note will remain available. There will be no result cap, source truncation, or per-line aggregation.

For a Fuzzy query with terms, column-sort actions will affect only the title group.
The sort affordance will state that scope. Programmatic sort changes must also leave the fuzzy group unchanged.
The title sort will form part of the presentation identity. Sort-only changes will reuse completed matching work.
Exact mode and queries without terms will apply the configured column order to the whole list.

When an edit makes the open note stop matching, the browser will keep that editor open.
If neither group contains that note, one retained editor row will appear after both groups.
That row will be marked as the current note outside the search results.
That row will not affect the match count, candidate cache, or first-result selection.
An explicit query or mode change will remove the retained row.

**Result rows and note identity**

A result row will have a stable key containing the note UUID and match kind: title, fuzzy, or retained editor.
The library lifetime and request identity will remain separate from that key.
Storage, editing sessions, and Undo will continue to use note UUIDs.
Two result rows for one note will therefore open the same shared document.
Exact mode and queries without terms will continue to show one row per note.

Selection, the primary selected row, and list scroll anchors will use row keys.
Refresh will preserve the selected occurrence instead of finding the first row with the same note UUID.
If that occurrence disappears, selection will fall back to the same note's surviving occurrence, then its retained editor row where applicable.
Switching between title and fuzzy rows for one note will update the search context and highlights.
It will preserve the attached editor storage, source caret, source scroll, and Undo history.

The list will report both result rows and distinct notes, such as “7 results in 5 notes.”
The retained editor row will remain outside those counts.
Creation will require a completed result with no rows in either matching group.
Multiple selected rows for one note will still count as one document for editing and command availability.

Note operations will resolve selected rows to unique note UUIDs, in first-selected-row order.
Delete, export, print, tags, external editing, and drag operations will act once per note.
Deletion confirmation will capture unique UUIDs and the library lifetime before opening the sheet.
Acceptance will resolve those targets again, rather than reuse row indexes from an older search result.
Deleting one note will remove all its result rows and register one deletion Undo operation.

**Ownership and data flow**

The implementation will use the ownership boundaries in [architecture.md](../architecture.md).
No browser will create a second library or share another browser's query state.

| Component | Responsibility |
| --- | --- |
| `NVApplicationController` | Own one search service for the active library. Invalidate its lifetime during replacement or restore. |
| Proposed `Sources/Search/NVSearchCorpus` | Hold immutable per-note snapshots, stable candidate order, note revisions, and the corpus revision. |
| Proposed `Sources/Search/NVSearchQuery` | Parse typed literal terms and quoted phrases. Preserve the original query for display and explicit creation. |
| Proposed `Sources/Search/NVSearchService` | Match literal titles, prepare fuzzy candidates, schedule background work, and return both memberships under one request identity. |
| C bridge in `Sources/Search/` | Construct native patterns, score complete candidates, return native order, and compute requested positions. |
| Proposed `NVSearchResultRow` and list adapter | Identify each occurrence and resolve its note explicitly for model access. Preserve match kind for presentation. |
| `NVBrowserSession` | Own search identities, mode, grouped result rows, row selection, the retained editor row, and presentation cache. |
| `AppController` | Apply current results to views. Route keyboard actions, creation, Reveal, and restoration through explicit completion paths. |

The main thread will capture committed title, tag, and source strings with the note UUID and revision.
Workers will receive immutable snapshots, never mutable `NoteObject` instances or shared `NSTextStorage`.
Prepared NFC and UTF-8 copies will be shared across browser requests.
Only changed notes will require preparation again.
Detailed Unicode range maps will be computed for requested highlights, rather than stored for every note.

Membership, title, tag, and committed body changes will invalidate search identity synchronously at their mutation boundaries.
This includes Undo, import, deletion, and external changes.
Snapshot preparation and browser refresh can coalesce after that invalidation.
An old completion must not publish between a model edit and a deferred browser refresh.
Font, color, preview, and layout changes will invalidate presentation only.

The corpus will remain in memory. This release adds no disk index or notes-format migration.
Prepared snapshots will share unchanged note versions.
Each browser will retain its displayed result and at most one pending replacement.
Workers will release obsolete snapshots after cancellation. The cache will not retain unbounded query or revision history.

**Asynchronous search contract**

The shared scheduler will support at most two serial worker lanes.
Each lane will own a reusable matcher slab and a worker autorelease pool.
Measurements will compare one and two lanes before the shipping worker count becomes final.
New queries will submit immediately, without a fixed debounce or permanent polling timer.

Waiting browsers will receive turns between bounded scoring batches.
The C bridge therefore needs a resumable job interface: begin, score a batch, then finalize.
The current prototype's single synchronous call cannot supply this scheduling behavior by itself.
One final native sort will order the complete fuzzy result set. The application will not combine separately ranked fuzzy batches.
Literal title matching will also run off the main thread on committed snapshots.
The session will apply its existing column comparator only to the title group after both memberships complete.
Detailed position work will have lower priority than current queries.

The request identity will include the library lifetime, corpus revision, browser lifetime, query, mode, and matcher settings.
A changed identity will advance that browser's request number.
An identical request will reuse active work or its completed result.
Displayed results will retain their own identity separately from the pending request.
Only a completion with the current identity can replace rows or enable search-dependent actions.

The first release will scan the complete prepared corpus for every Fuzzy query.
The existing candidate-refinement optimization will remain confined to Exact mode.
No native membership cache will assume an append-only corpus.
Publication will occur once, after title matching, fuzzy scoring, and native sorting complete for the captured revision.
The result will carry both groups, their match kinds, row counts, and distinct-note counts.
Partial scans or an empty title group cannot establish zero matches.

| Browser state | UI and action rules |
| --- | --- |
| Current result | Rows and their actions are available. Counts, positions, and identities belong to the same result. |
| Pending request | Prior rows remain visible with an unavailable state. A delayed “Searching…” label appears after 100 ms. |
| Failed request | Show one error with Retry. Retained rows remain unavailable, and failure does not imply zero matches. |
| No terms | Cancel pending work and show the configured all-notes order immediately. |

An unavailable row cannot supply pointer selection, arrow navigation, Home/End, Tab activation, context actions, drag operations, or bulk note operations.
Actions on the already open editor can continue through its explicit note identity.
An explicit New Note command can also continue.
This distinction prevents stale row indexes from targeting a different note.

Return during a pending Fuzzy query will record one intent for that exact request and original query text.
After completion, it will open the selected result or the first displayed row, with title matches before fuzzy matches.
It can create a note only when both completed groups are empty.
A query, mode, focus, selection, or corpus change will cancel that intent. Escape and composition start will also cancel it.
The completion must never read a newer field value as the creation title.
Failures will remain terminal until Retry or an identity change.

Publication will use a coalesced main-queue callback, with ownership checks before presentation work and immediately before row replacement.
The callback will carry request origin and selection/focus epochs instead of retaining a synchronous typing flag.
It will capture the latest selection before replacement and preserve active table-field editing rules.
An obsolete callback cannot overwrite a newer selection, mark newer output as displayed, or suppress its notification.
Closing a browser will invalidate ownership immediately, without a main-thread worker join.

Search-field composition will invalidate the publication identity and pending Return immediately.
Prior rows will become unavailable, and query or position completions cannot publish during composition.
Composition end will establish a fresh request identity, even when the committed query equals its earlier value.
That request can reuse a valid cached result without accepting an older callback.
Source composition will retain the existing shared-editing contract and enter the corpus only after commit.

In Fuzzy mode with autocomplete enabled, an explicit query or mode submission can select a result while focus remains in search.
The existing shortest-title-prefix preference will apply within the title group. Its fallback will be the first displayed result.
Exact mode will retain its existing no-selection behavior when no title prefix matches.
Corpus-only refreshes will preserve the open editor and selection, including a retained nonmatching row.
Autocomplete must not steal focus or replace a later explicit selection.

**Existing integration points**

The browser filter lives in [NVBrowserSession.m](../Sources/Browser/NVBrowserSession.m), rather than the old filter in `NotationController`.
Its current parser discards quote metadata, and its visible-array sorter also sorts retained editor rows.
Both assumptions need explicit mode-aware replacements.
[AppController.m](../Sources/Browser/AppController.m) currently expects filtering, selection, and creation to complete synchronously.
Existing list helpers also assume that a note has one row.
The implementation must separate row lookup from unique-note lookup at the list adapter boundary.
Some C column callbacks and inline editors directly access `NoteObject` fields.
Row wrappers cannot replace those objects through message forwarding. The adapter must resolve the model explicitly and retain row-aware presentation callbacks.

| Existing path | Required integration |
| --- | --- |
| `controlTextDidChange:`, `fieldAction:`, table selection, and search-field commands | Separate query submission from result publication. Use the current-result check for every row-dependent action. |
| Model mutation and `NVApplicationController` refresh paths | Advance corpus identity before deferred refresh. Keep display-only refresh separate. |
| `FastListDataSource`, `NotesTableView`, and browser selection helpers | Add row-key selection and scroll lookup. Resolve unique note targets separately for commands and inline editing. |
| `AppController_MultipleWindows.m` restoration | Defer saved note and row state until search completes: UUID, match kind, selection, source/preview mode, viewer state, and scroll. |
| Bookmarks, saved searches, last-search preferences, followed links, and snapback | Store mode with query. Decode missing mode as Exact and preserve mode during library attachment. |
| `nv://find`, AppleScript search, and wiki-link title fallback | Preserve Exact semantics for existing callers. |
| Single-note and multi-note Reveal, including imports and creation | Wait for current membership before deciding that the query excludes a note. Retain background, nonactivating behavior. |

Restoration and Reveal will retain the requested identities and options until their current search completes.
A newer query, library lifetime, or explicit selection will supersede obsolete intents.
Restoration will not apply note-dependent state to a temporary first result.
Reveal will not clear a query based on pending rows.
Saved state will store an optional match kind with the selected UUID.
Note-only Reveal will preserve a valid selected occurrence, otherwise prefer the title row, then the fuzzy row.
Legacy state without a match kind will use the same preference.
Multi-note Reveal will select one representative row per requested unique note.

**Excerpts and source highlights**

The list will request positions only for visible rows, and the source editor only for the primary selected row.
Title rows will use literal title ranges and the usual opening excerpt. They will not depend on native membership or positions.
Their source highlights will use existing literal matching where the terms also appear in the body.
Fuzzy rows will use native positions and show context around the first body position.
When a fuzzy result matches only the title or tags, its row will retain the usual opening excerpt.

Excerpt and position caches will include the row key, request identity, and source revision.
They will be bounded and separate from ordered results.
Appearance and preview-visibility changes will not rescore notes.

The adapter will map native codepoint positions through NFC copies to original Cocoa UTF-16 and composed-character ranges.
Search backgrounds will use each editor's layout manager temporary attributes.
They will preserve source characters, Undo, syntax foreground colors, and independent highlights in peer windows.
An edit will clear stale ranges immediately.
Incompatible uncommitted text in shared storage will suppress snapshot highlights until its content matches the searched revision.
In-note Find and rendered-preview Find will retain their existing behavior.

**Native dependency and production boundaries**

The implementation will vendor the pinned matcher subset into `ThirdParty/fzf-native/`.
This includes the matcher, required supporting files, utf8proc runtime/data, and original MIT and Unicode notices.
The extracted batch code will retain its GPL-3.0-or-later notices and [provenance](../Prototypes/FuzzySearch/Core/ORIGIN.md).
The Emacs module, Lisp frontend, shell reader, prebuilt binaries, and upstream build system are unnecessary.
The Xcode target and CI will build from the repository without the ignored prototype download.

The production bridge will accept typed terms directly and use native pattern initialization.
It will not implement literal punctuation through ad hoc escaping of the native query language.
The native multi-term scorer will remain responsible for the whole candidate's score.
The existing production Exact path will remain separate from this fuzzy adapter.
The prototype and app will share the promoted C implementation to prevent divergent copies.

Native calls will report allocation errors without partial publication.
The adapter will clear and inspect the native allocation-error flag around relevant calls.
Tests will inject failures into pattern construction, scoring, slabs, normalization, position work, and result allocation.
Objective-C wrappers will handle engine and cancellation-token creation failure and explicit retain/release ownership.

The initial bridge limits will remain explicit: 65,536 UTF-8 query bytes, `INT32_MAX` candidate bytes, and `UINT32_MAX` candidates.
Candidate NUL bytes will remain searchable. An embedded query NUL or exceeded limit will produce an error.
The prototype's folder-import limits will not become production corpus exclusions.
An unsupported input or exhausted allocation must never silently omit a note or become a zero-match result.

**Delivery sequence and acceptance**

1. **Promote the C foundation and query parser.** Vendor the pinned source subset and notices. Add the typed pattern builder and resumable scoring interface. Retain independent upstream-order comparisons, including resumed scans and native fallback paths.
2. **Add corpus and request ownership.** Add synchronous mutation invalidation, immutable preparation, both matching paths, bounded scheduling, cancellation, and explicit result states. Exercise these paths before browser activation.
3. **Integrate the complete browser workflow.** Add title-first groups, duplicate result rows, Fuzzy/Exact controls, action checks, creation, restoration, and Reveal. Keep Fuzzy opt-in during development.
4. **Add excerpts and source highlights.** Port Unicode mapping and temporary attributes. Keep position work separate from scoring and preserve the existing syntax-color behavior.
5. **Validate the default.** Build the Intel app. Run native and desktop suites, record performance, and update architecture and user documentation. Report unmet checks explicitly.

| Check group | Required evidence |
| --- | --- |
| Query and ordering | Literal punctuation, quoted/unclosed phrases, mixed terms, empty terms, native ties and saturation, UUID producer order, and complete ordered-ID parity. |
| Title priority and duplicate rows | Title-only membership, body-only matches below titles, overlapping groups, independent column sorting, repeated UUIDs, and unchanged complete fuzzy order. |
| Mutable corpus | Additions, deletions, equal-count edits, title/tag changes, Undo, imports, external changes, and cache reuse equal fresh full searches. |
| Async ownership | Reordered and duplicate callbacks, cancellation during each stage, several windows, closure, library replacement, errors, Retry, and no unbounded retained snapshots. |
| Browser behavior | Return while pending, explicit creation, stale-row actions, autocomplete, retained editor rows, hidden notes list, Reveal, and full state restoration. |
| Row and note identity | Duplicate-row selection, scroll anchors, same-note context changes, row restoration, unique-note command targets, deletion Undo, and stale confirmation dialogs. |
| Shared editing and presentation | Search/source composition, two editors on one note, independent source highlights, preview mode, system appearance, and no syntax-color flicker. |
| Text and allocation | NFC/NFD, accents, CJK, emoji, combining marks, NUL, long lines, invalid-input limits, allocation errors, leaks, and use-after-free checks. |

The shipping configuration remains Intel with the macOS 10.13 deployment target.
The prototype's native arm64 build and macOS 12 interface do not establish this compatibility.
Required application commands are:

```sh
xcodebuild -project Notation.xcodeproj -scheme 'Notation Develop' \
  -derivedDataPath build/DerivedData ARCHS=x86_64 \
  MACOSX_DEPLOYMENT_TARGET=10.13 CODE_SIGNING_ALLOWED=NO \
  GENERATE_PROFILING_CODE=NO OTHER_CFLAGS= WARNING_LDFLAGS= build
python3 Tests/run-multiple-windows-tests.py
python3 Tests/run-regression-tests.py
```

The focused C suite will also run in the shipping configuration and under sanitizers where supported.
CI can run headless native checks. The two desktop suites require an active macOS desktop and disposable notes.
CI changes will also require `python3 -B -m unittest discover -s Tests/CI -v`.

Performance measurements will include 1,000 and 10,000 notes, a 50 MiB corpus, and individual 1–8 MiB source lines.
They will record both matching passes, title sorting, duplicate-row publication, cancellation, position work, peak memory, and competing windows.
Cold preparation and warm queries will have separate measurements.
The record will identify the hardware, macOS/Xcode versions, architecture, corpus bytes, and query distribution.

| Proposed release target | Scope |
| --- | --- |
| Main-thread work below 8 ms at the 95th percentile | Query handling and result publication, measured separately. Initial snapshot capture and edit snapshots also require measurement. |
| Warm completed search within 150 ms at the 95th percentile | A recorded Intel test machine, 10,000 notes totaling 50 MiB, and representative queries of at least three characters. |
| Obsolete work releases its lane within 100 ms | Preparation, native matching, rank-key calculation, sorting, and highlight positions, including the long-line fixtures. |

These were initial proposals, not measured guarantees. The implementation measurement revises the 150 ms release gate to a performance follow-up.
On arm64, a 10,000-note corpus of about 50 MiB requires roughly 0.5–1.3 seconds in the native scorer alone.
The app keeps complete results and native order; it does not claim the original latency target.
The [first performance review](../Tests/FuzzySearch/Review/round-1/luu/findings.md) also measured about 35–38 ms to publish 20,000 occurrences.
That fixture exceeds the proposed 8 ms publication target and excludes real table painting.
Both targets remain performance follow-ups, without changing membership or native order.
Intel latency, complete UI publication, and desktop behavior still require runtime validation.
One native matcher call remains uninterruptible. Cancellation measurements must include individual large notes.
It must not truncate notes, alter the fuzzy group's native order, or label incomplete output as a complete search.

The defaults proposed for review are Fuzzy for new sessions, Exact for legacy state, complete-note candidates, and nv's literal query syntax.
Title matches will appear first, and a note can appear in both groups.
The native-order requirement applies to the complete fuzzy group.
The main unresolved engineering question is whether complete-note matching meets the Intel latency and cancellation targets without upstream matcher changes.
