# Round 1: ownership and interface review

This review used an architectural lens inspired by John Ousterhout. It does not represent his review or opinions.

The bounded review found no actionable defect in search ownership, request reuse, callback publication, or coordinator invalidation. No P0–P3 finding requires a production change.

The application baseline was `a9539cca76e260546310caa4918d018f802b064b`. The reviewed implementation is committed at `c7e61cbd5cd863cc285d09614b4cd3a2b18e11e7` in PR 10.

## Scope

The review covered the service, corpus, query, browser session, and application coordinator. It also traced model notification hooks and browser detach paths.

The ownership boundary keeps native work inside one service. The coordinator copies committed values before work reaches the serial queue. Browser sessions retain query state and row identity. Source positions use a separate request channel from visible excerpts.

The review read `AGENTS.md`, `architecture.md`, and `docs/fuzzy-search-plan.md`. `reviewed-inputs.json` records the source hashes and the final HEAD.

## Executable evidence

The host used arm64, macOS 26.5.2 (25F84), and Xcode 26.6 (17F113).

| Command | Result |
| --- | --- |
| `python3 Tests/FuzzySearch/Review/round-1/ousterhout/run.py` | 64 checks passed. |
| `python3 Tests/FuzzySearch/Review/round-1/ousterhout/run.py --sanitize` | 64 checks passed. AddressSanitizer and UndefinedBehaviorSanitizer reported no errors. |
| `python3 Tests/FuzzySearch/Review/round-1/ousterhout/run-coordinator.py` | 19 checks passed. |
| `python3 Tests/FuzzySearch/Review/round-1/ousterhout/run-coordinator.py --sanitize` | 19 checks passed. AddressSanitizer and UndefinedBehaviorSanitizer reported no errors. |

`ownership-probe.m` links the production service, corpus, query, C bridge, and pinned native matcher. A snapshot subclass pauses preparation for the request-reuse case. Its superclass constructs the candidate bytes. The production matcher computes every result.

`run-coordinator.py` compiles six unchanged production coordinator methods with the production browser session and service. The fixture supplies in-memory model and browser dependencies. It reuses supporting doubles from the existing browser test file. It does not modify that file.

The four result JSON files retain commands, exit codes, output, and hashes for executable inputs.

## Negative findings

- Pending identical requests reused one identity and delivered only the replacement callback. The result retained both matching groups and their overlap.
- Fifty requests submitted from callbacks completed without synchronous delivery or a lost callback. Completed matching work retained its request identity.
- A corpus mutation inside a completion invalidated that request synchronously. The replacement request returned the new source content.
- Equal committed strings preserved the corpus identity. Changes to title, tags, and source each invalidated the old request identity.
- Source-position replacement suppressed the obsolete callback. Independent excerpt and peer-browser position requests completed.
- Browser cancellation also cancelled both of its position channels. The peer browser retained its current request.
- Library replacement suppressed the old callback. A reused note UUID resolved the new library's snapshot.
- A cancelled service released its callback capture and obsolete snapshots without a worker join.
- Coordinator mutations invalidated two browser sessions before the run loop resumed. Each query then completed against the changed shared corpus.
- Display refresh and unchanged model notifications preserved both browser request identities.
- Removal dropped every occurrence after refresh. A later callback from the detached model did not reinsert its UUID.

## Limits

The executable coordinator fixture does not exercise the full application, file storage, AppKit window lifecycle, or source composition. The lifecycle conclusion covers service replacement and cancellation.

The review traced the production close and library-attachment paths. It did not run the Intel application because that runtime stalls on this host.

The sanitizer checks cover the exercised paths. They do not establish the absence of all leaks or races. This review does not establish Intel latency.

No production file or original test file changed during this review. All review additions belong to this evidence directory.
