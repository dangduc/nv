# Resolution of the round 1 retry finding

`LinkingEditor` now requests a 10 ms delay before each cleanup retry while character editing remains open.
The first invalidation still requests a zero-delay callback after the current event.
The pending flag keeps stale search backgrounds suppressed throughout the wait.
Safe cleanup clears that flag and removes the temporary backgrounds.

The change retains the character-edit guard and the existing cancellation selector.
Fresh highlights and note switches can cancel the delayed callback through `removeHighlightedTerms`.
No new timer ownership, observer, or editor field is necessary.
The delay bounds retry frequency. It does not limit the total retries for an edit batch that never ends.

The resolution probe extracts three production methods into an editor adapter with real AppKit storage, layout, and run-loop callbacks.
Default-mode and event-tracking workloads each scheduled five cleanup callbacks during an open editing batch of approximately 50 ms.
Each workload completed one safe layout removal after the batch ended.
The probe passed 20 checks, including background suppression, foreground preservation, cancellation before fresh publication, and cancellation before storage replacement.
The zero-delay negative control failed at the expected minimum-delay assertion.

The delay assertion reads the scheduling argument directly. It has no machine-dependent latency threshold.
An additional operation-count assertion allows twice the configured retry rate plus two callbacks, based on measured elapsed time.
The count allowance accommodates timer precision without permitting the reported zero-delay loop.

The maintained HighlightBounds suite passed 134 checks in each of three builds: native, Intel, and native AddressSanitizer/UndefinedBehaviorSanitizer.
All 11 mutation controls failed at their expected assertions.
The added checks cover delayed retries, coalescing, safe cleanup after `endEditing`, and cancellation before fresh range publication.
The unsafe-clear mutation still removes the character-edit guard. A new mutation restores zero-delay retries.

The resolution probe ran on macOS 26.5.2 through Rosetta.
It did not open a GUI app or personal notes. It did not run on macOS 13.
The editor adapter omits browser ownership and full window drawing.
The parent task owns the final application build and copied-app validation.

Run the resolution probe:

```sh
python3 Tests/SourceBackspaceReview/fixes/retry/run.py
```

Run the maintained checks:

```sh
python3 Tests/FuzzySearch/HighlightBounds/run.py --negative-controls
python3 Tests/FuzzySearch/HighlightBounds/run.py --arch x86_64
python3 Tests/FuzzySearch/HighlightBounds/run.py --sanitize
```

`manifest.json` records the production and generated-probe hashes.
`positive.txt` and `zero-delay-negative-control.txt` contain the probe results.
The compilation logs contain no warnings.
The earlier round 1 evidence remains unchanged.
