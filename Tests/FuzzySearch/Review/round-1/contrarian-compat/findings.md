# Round 1: persistence and command compatibility

The review found two P2 regressions. Both concern mode compatibility. The review accepts the required duplicate result rows and complete native order.

The affected methods match implementation commit `c7e61cb` byte for byte. Each result record contains method hashes and this comparison.
The workspace reached `6815101` during this review. Other reviewers changed search-focus and highlight code while these checks ran.
The records identify those inputs separately. This review changed no production file or original test file and created no commit.

Environment: macOS 26.5.2, build 25F84. Xcode 26.6, build 17F113. All executions used native arm64.

## P2: restore Exact for a present legacy empty search

Location: `Sources/Browser/AppController.m`, lines 1627–1633 in `c7e61cb`.

Trigger: preferences contain `LastSearchString = ""`, omit `LastSearchMode`, and contain no browser-window state that overrides the last-search fallback.
The initial library attachment supplies the new Fuzzy default. The restoration method changes mode only for an explicit saved mode or a nonempty query.
It therefore treats a present legacy empty query like absent search preferences.

Observed result:

```text
LEGACY EMPTY: stored_query=present-empty stored_mode=absent restored_mode=fuzzy
FAIL: a present legacy empty search restores Exact
```

The empty list initially looks unchanged. The next typed query uses Fuzzy despite the saved legacy context's Exact semantics.
The correction must distinguish absent last-search preferences from a present empty legacy query. Fresh sessions must retain Fuzzy.

Controls passed: absent defaults keep Fuzzy, a nonempty legacy query restores Exact, and an explicit empty Exact query restores Exact.
Mode-less browser-window dictionaries also restore Exact. That passing path limits this finding to the last-search fallback.

## P2: preserve Fuzzy mode during Tab autocomplete

Location: `Sources/Browser/AppController.m`, lines 1089–1092 in `c7e61cb`.

Trigger: autocomplete is enabled, a Fuzzy query completes, the user deselects its note, and the user presses Tab in search.
The production selection callback clears `currentNote`. The preferred result remains valid.
The Tab branch calls `searchForString:`, which now forces Exact for legacy callers. An internal browser command therefore changes the current mode.

The fixture contains a title match, a literal body match, and a body match with gaps. Its Fuzzy result contains four rows over three notes.
After Tab, the same query uses Exact and contains two rows:

```text
TAB: handled=1 query=road restored_mode=exact rows=2
FAIL: Tab autocomplete preserves the active Fuzzy mode
```

The English main menu exposes `Deselect Note(s)` through `deselectAll:` in `Resources/Localization/en.lproj/MainMenu.xib`, lines 464–466.
The probe runs the production deselection callback and the complete production search-field command method. Its table sends the same selection notification.
The correction must pass the browser's current mode from this internal call. The mode-less external selector must remain Exact.

## Executable evidence

The runner extracts production methods at execution time. It compiles the real browser session, corpus, search service, and native matcher.
Deterministic controls and in-memory notes replace the desktop and disk library. A separate defaults object prevents access to personal preferences.

| Command | Result | Record |
| --- | --- | --- |
| `python3 Tests/FuzzySearch/Review/round-1/contrarian-compat/run.py` | Pass, 59 checks, including two failure witnesses | `native-results.json` |
| `python3 Tests/FuzzySearch/Review/round-1/contrarian-compat/run.py --sanitize` | Pass, 59 checks, no address or undefined-behavior diagnostic | `sanitize-results.json` |
| `python3 Tests/FuzzySearch/Review/round-1/contrarian-compat/run.py --expect-fixed legacy-empty` | Expected exit 1 at the legacy-mode assertion | `legacy-empty-results.json` |
| `python3 Tests/FuzzySearch/Review/round-1/contrarian-compat/run.py --expect-fixed tab-mode` | Expected exit 1 at the Tab-mode assertion | `tab-mode-results.json` |

After both corrections, `--expect-fixed all` requires both intended behaviors. The sanitizer flag can accompany this option.

## Passing compatibility checks

- Missing and invalid bookmark and saved-search modes select Exact. Invalid outer archive shapes and non-string bookmark UUIDs are rejected.
- Bookmark equality and hashes survive lazy model resolution, deletion, and later resolution. Each UUID resolves to the fixture's shared model.
- Title and Fuzzy bookmark occurrences remain distinct. Saved-search equality remains query-plus-mode while its selected occurrence changes.
- Invalid occurrence types fall back to note identity. Window restoration rejects a valid row key that belongs to another note.
- Legacy `nv://find` and direct `searchForString:` calls select Exact. The followed-link stack restores the previous Fuzzy mode and occurrence.
- The bookmark command restores its saved Fuzzy occurrence after current search completion.
- Mode-less and invalid-mode window dictionaries restore Exact and the intended note.

## Limits

The probe does not run the full Intel app. Rosetta execution stalls on this host, so no Intel process ran.
The UI doubles establish production command and callback behavior. They do not establish native keyboard focus delivery or menu interaction through AppKit.
The menu connection supplies source evidence for the deselection action. The original desktop suites remain outside this focused review.
The startup probe supplies the initial Fuzzy session that `attachLibrary:` creates. It exercises the complete production last-search restoration method afterward.
The saved-search controller remains outside the application target. This probe covers its archive model, not its obsolete preference-storage API.
UUID string acceptance follows `CFUUIDCreateFromString`. This review does not impose a stricter parser than the platform supplies.
Return timing and highlight performance belong to the other round-one reviews.
