Round three found no new actionable compatibility defect in the checked Exact search boundary.
This independent contrarian review challenged whether Fuzzy support changes legacy Exact behavior through shared session code.

The native and sanitizer runs each passed 1,397 assertions across 274 comparisons with the pre-PR implementation.
The sanitizer run produced no address or undefined-behavior diagnostic.
The negative control failed at the expected semantic difference.

**Independent legacy oracle**

The runner compiles the complete `NVBrowserSession.h` and `.m` from the PR merge base, `a9539cca76e260546310caa4918d018f802b064b`.
It renames `NVBrowserSession` to `LegacyExactSession` in those copied files. It makes no algorithm changes.
Both complete session implementations run against the same in-memory notes, library, preferences, and sort-column fixtures.

The current session, parser, corpus, service, and native search sources match production commit `11f571f`.
Each run captures tracked sources before compilation. It excludes ignored files.
The JSON records contain the captured HEAD, production source hashes, legacy source hashes, fixture hashes, and generated probe hash.
All recorded production inputs matched `11f571f` in both runs.

**Commands and results**

| Command | Result | Record |
| --- | --- | --- |
| `python3 Tests/FuzzySearch/Review/round-3/contrarian-compat/run.py --negative-control` | 1,397 assertions passed; mutation rejected | `native-results.json` |
| `python3 Tests/FuzzySearch/Review/round-3/contrarian-compat/run.py --sanitize` | 1,397 assertions passed; no sanitizer diagnostic | `sanitize-results.json` |

The runs used native arm64 on macOS 26.5.2 (25F84), with Xcode 26.6 (17F113).
No application window, notes directory, or Intel process was opened.

**New executable evidence**

The fixture uses 18 notes and 43 queries, with title, body, and tag matches.
Each query sequence runs through three entry routes in both sort directions:

- `filterNotesFromString:`.
- `filterNotesFromUTF8String:forceUncached:NO`.
- `filterNotesFromUTF8String:forceUncached:YES`.

Each comparison requires identical ordered note objects, autocomplete row, and query text.
It also requires synchronous current Exact results and equal row and distinct-note result counts.

The sequences include refinements, broadenings, empty queries, separators, quote changes, quoted newlines, punctuation, composed and decomposed accents, and emoji.
Explicit expected-result assertions supplement the legacy oracle:

- `road:copper` finds two notes through requirements across title, body, and tags.
- `"red blue"` requires adjacent text within one field.
- Unquoted terms can match across all three fields.
- `!road` keeps literal punctuation, and Exact excludes a gapped `r---o---a---d` body.

Further comparisons cover an edited open note, a new note, and a deleted note during a refined search.
The edited note remains a retained row, then leaves the next query's search candidates.
Model invalidation admits the new match and removes the deleted match in both implementations.

Four real asynchronous Fuzzy searches run between Exact comparisons.
Returning to Exact restores the legacy result order and autocomplete behavior.
A second browser retains its Exact mode, rows, and search generation throughout those Fuzzy searches.
Disabling autocomplete after the mode changes still returns no preferred row.

The negative control removes colon from the current session's separator set in the copied source only.
For `road:copper`, the mutated session returns zero results while the legacy session returns two.
The ordered-result assertion rejects that difference. The runner restores and recompiles the unmodified source afterward.

**Limits**

This review compares the session behavior against the previous implementation, not an independent definition of every Cocoa string rule.
Both implementations use the same native Foundation string operations.
The notes have distinct sort titles. The review does not compare the newly defined UUID ordering for equal titles.
The sort column, model storage, and delegate callbacks are fixtures. Full application startup, nib loading, and AppKit event dispatch remain outside this review.
Saved-state defaults and bookmark restoration remain the previous round's scope. This round does not repeat that 279-assertion matrix.
The Fuzzy cases establish mode isolation and return-to-Exact behavior. They do not provide another independent native ranking oracle.
The host's Intel startup stall still prevents the full desktop suites.

This review changed only files in its round-three directory. It changed no production file and created no commit.
Generated sources, compiler logs, and the mutation output are under `build/FuzzySearchReview/round-3/contrarian-compat/`.
