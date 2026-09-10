# Round 2: contrarian UX review

No actionable defect reproduced in this round.

Reviewed the production diff from `8dde5e8` to `5eda58b`, AGENTS.md, and architecture.md. Wrote and ran a new native probe against the compiled production app. The test uses a copied app, unique preferences domain, and disposable notes. It does not access the normal application library.

Command:

```sh
python3 Tests/TypingReview/round2/contrarian_ux/run.py --output build/TypingReview/round2/contrarian_ux
```

Result: **19 checks passed**, native exit 0. These include four isolation/startup checks. `output.txt`, `results.json`, and `environment.json` record the run, binary SHA-256, and environment.

The production native controls passed these new cases:

- A hidden word-count control opens through `popWordCount:`, receives its first asynchronous count, and clears on hide.
- Showing and immediately hiding the popup while analysis is pending leaves the hidden label empty after completion. Showing it again obtains the new count.
- Two browser windows share one note storage and display the same count after a peer edit.
- Switching one window to another note while a count is pending preserves the two correct labels: seven words for the new note and six for the peer's original note.
- Closing the last browser attached to the original note while analysis is pending does not crash. Reattaching that note computes its latest eight-word count.

Limits: the popup helper supplies an `NSFlagsChanged` event through a scoped `NSApplication.currentEvent` override while calling the production `popWordCount:` method. It does not test the physical Option-key hold or 1.2-second modifier timer. Actual workers, shared storage, window creation/closure, edits, notifications, and controls are unchanged. Short notes exercise scheduled pending work; this run does not establish behavior during a long indivisible word-count worker call. The first sandboxed launch aborted before startup with signal 6 and no assertions; the authorized copied-app run and its clean rerun both passed.
