# Round 3: static API and ownership review

This agent review uses a John Ousterhout-inspired perspective. It does not represent a review by John Ousterhout.

One P3 documentation clarification is requested. No new runtime defect is established.

This round uses static source evidence only. The originally requested native lifecycle experiment was stopped before implementation. No editor was executed, no crash was reproduced, and no new native test was run for this round.

## P3: qualify the note-switch cleanup guarantee

`architecture.md:114` states that note switches clear old backgrounds and cancel cleanup before the layout manager changes storage.

The source has a conditional contract. `LinkingEditor.m:479` first cancels pending cleanup. If character editing remains open, it schedules another cleanup and returns. `AppController.m:1198` calls that method before moving the layout manager, without inspecting whether removal completed or was deferred.

The documentation therefore describes the immediate path as an unconditional guarantee. Qualify it to the path outside character editing. State that the guard defers removal while a character transaction remains open. Fresh highlight publication cancels pending cleanup.

This is a documentation request. Static evidence does not establish that note switching can enter that guarded path in the application. It does not establish a crash, visible artifact, or ownership failure.

## API assessment

The inventory reads 224 source files. It locates one declaration and one definition for each of five public highlight methods:

| Method | Direct call sites | Selector references |
| --- | ---: | ---: |
| `removeHighlightedTerms` | 6 | 4 |
| `invalidateSearchHighlights` | 1 | 0 |
| `setSearchHighlightRanges:` | 1 | 0 |
| `highlightRangesTemporarily:` | 0 | 0 |
| `highlightTermsTemporarilyReturningFirstRange:avoidHighlight:` | 1 | 0 |

The new public invalidation method has a caller in the controller's shared-storage observer. It gives that observer one operation without exposing timer state or temporary-attribute mechanics.

The editor owns `searchHighlightsInvalidated`. Its seven textual references stay in `LinkingEditor.h` and `LinkingEditor.m`. The browser owns the separate generation counter, which rejects obsolete async results. These states serve different purposes: local display cleanup and request validity.

Cleanup cancellation, the character-edit guard, and background removal remain in one editor method. Existing direct callers reuse that boundary. The controller still owns storage attachment and observer registration.

The inventory finds no source call to the older `highlightRangesTemporarily:` API. That public method already existed at base `54ce3b8`. Its possible removal is separate cleanup, not a requested change to this fix. Text matching cannot prove the absence of dynamic calls or external consumers.

## Evidence and limits

Run:

```sh
python3 Tests/SourceBackspaceReview/round3/ousterhout/inventory.py
```

The script reads production source and writes review evidence only. `output.json` records declarations, definitions, call sites, state references, ownership excerpts, and the architecture paragraph. Three inventory consistency checks pass. These are static checks, not runtime tests.

`manifest.json` records commit `bfaebae`, the architecture hash, and four matching production hashes before and after the inventory. No production file changed.

This review does not validate dynamic dispatch, lifecycle timing, input methods, rendering, or the user's macOS 13.7.8 environment. Prior rounds retain their separate runtime evidence; this round adds none.
