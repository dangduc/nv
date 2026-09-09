# Adapting fzfa asynchronous search to nvALT

The recommendation is to adapt the request and publication protocol from `fzfa`.
Native fuzzy scoring and sorting will remain in `fzf-native`. nvALT will supply its own immutable note corpus and Cocoa interface.
The revised [search plan](fuzzy-search-plan.md) places literal title matches above the complete fuzzy group.
A note can have a result row in both groups. Native order remains unchanged within the fuzzy group.
This audit informed the implemented search service. The linked plan records integration choices and validation limits.

The audit covers [`fzfa` at `8d4fd2c`](https://github.com/jojojames/fzfa/tree/8d4fd2cf7e58d8055bbcccbeb54c31978f9413bf)
and [`fzf-native` at `4b9236e`](https://github.com/dangduc/fzf-native/tree/4b9236e8cd1e9f9f3aaf5f2ebf83f1fc5995d38d).

`fzfa` has two relevant paths. Shell-command sources use persistent native reader, coordinator, and worker threads.
A callback can supply in-memory candidates asynchronously. Their batch scoring still occurs synchronously.
Thus, the existing in-memory entry point cannot directly supply background search for nvALT.
This distinction appears in the [candidate-source dispatch](https://github.com/jojojames/fzfa/blob/8d4fd2cf7e58d8055bbcccbeb54c31978f9413bf/fzfa.el#L4983).

Within each async source, the frontend preserves native candidate order for nonempty queries.
Other paths can apply history ordering or group sources. nvALT will preserve native order within its fuzzy group.
The application will place title matches first without changing fuzzy scores or removing repeated note identities from the fuzzy output.
The relevant branch is in [`fzfa--sort-by-history`](https://github.com/jojojames/fzfa/blob/8d4fd2cf7e58d8055bbcccbeb54c31978f9413bf/fzfa.el#L2136).

| Mechanism | Evidence | Adaptation for nvALT |
| --- | --- | --- |
| Submit each distinct request once | The source retains a request signature, native ID, and ownership epoch. Equal redraws reuse the request. [Request submission](https://github.com/jojojames/fzfa/blob/8d4fd2cf7e58d8055bbcccbeb54c31978f9413bf/fzfa.el#L2692) | Include the library lifetime, corpus revision, browser lifetime, query, and all matching options. Redraw must not restart scoring. |
| Reject obsolete publication | Ownership is checked after snapshot construction. An outer callback cannot replace newer output from a nested callback. [Snapshot publication](https://github.com/jojojames/fzfa/blob/8d4fd2cf7e58d8055bbcccbeb54c31978f9413bf/fzfa.el#L2839) | Check ownership before presentation work and immediately before the main-thread result swap. |
| Separate results from presentation | Snapshot generation and highlight policy identify the prepared display output. [Presentation key](https://github.com/jojojames/fzfa/blob/8d4fd2cf7e58d8055bbcccbeb54c31978f9413bf/fzfa.el#L2728) | Cache ordered note IDs separately from visible excerpts and temporary highlights. Color or preview changes do not rescore the corpus. |
| Distinguish pending from empty | Empty partial results remain pending. Only a final result can clear the display. [Result state](https://github.com/jojojames/fzfa/blob/8d4fd2cf7e58d8055bbcccbeb54c31978f9413bf/fzfa.el#L2819) | Keep prior rows during work. Only the current completed result can enable creation from a zero-match query. |
| Retain terminal errors | A failed request is reported once and cached for its signature. [Failure handling](https://github.com/jojojames/fzfa/blob/8d4fd2cf7e58d8055bbcccbeb54c31978f9413bf/fzfa.el#L2882) | Show one error state. Retry requires an explicit retry or a changed request identity. Repainting cannot create a failure loop. |
| Avoid repeated result copies | A timer polls metadata. Candidate strings are prepared only for a new result or presentation policy. [Generation polling](https://github.com/jojojames/fzfa/blob/8d4fd2cf7e58d8055bbcccbeb54c31978f9413bf/fzfa.el#L1978) | Push a coalesced notification to the main queue. Transfer ordered IDs once and retain the immutable corpus snapshot. |

The timer values do not define a recommended search delay for nvALT.
`fzfa` polls every 50 ms and throttles incoming-data display updates to 200 ms.
Its 100 ms debounce retries an interrupted display fetch. Native scoring continues independently.
These settings exist for the Emacs event loop. See the [timer definitions](https://github.com/jojojames/fzfa/blob/8d4fd2cf7e58d8055bbcccbeb54c31978f9413bf/fzfa.el#L165).
nvALT will submit changed queries immediately, replace obsolete queued work, and coalesce main-queue notifications.
A completed result will not wait for a fixed debounce period.

The native coordinator scores batches outside the frontend and preserves producer indices through compaction.
With unlimited results and full scoring, it globally sorts all matches before publication.
Its [abortable radix sorter](https://github.com/dangduc/fzf-native/blob/4b9236e8cd1e9f9f3aaf5f2ebf83f1fc5995d38d/fzf-native-module.c#L5661)
includes a heap-sort fallback for scratch allocation failure. Both use the native total order.
This is the sorter to extract for nvALT's C adapter, together with the existing score-key calculation.

The output contract depends on the native mode:

| Native mode | Result contract | nvALT choice |
| --- | --- | --- |
| Full scoring, unlimited results | Complete matching set in global native order for the captured corpus boundary. | Use this path. |
| Full scoring, positive limit | Global top K for the captured boundary, using reductions across batch windows. | Defer while the notes list requires every match. |
| Filter-only, positive limit | Rank the first K matching candidates in producer order. This is not global top K. | Exclude. |

The distinctions appear in the [coordinator's final sort and emission](https://github.com/dangduc/fzf-native/blob/4b9236e8cd1e9f9f3aaf5f2ebf83f1fc5995d38d/fzf-native-module.c#L6988).
Retained output is a previously completed result. It can belong to an older query or an earlier producer boundary.
It is not an unsorted fragment of the current scoring job.
nvALT already has a finite corpus snapshot for each request.
The first release will publish both groups once, after literal title matching and native fuzzy scoring and sorting complete.
Progress can update independently. Row keys, row counts, distinct-note counts, and corpus revision will come from the same completed result.

The native session's append-only cache is unsuitable for direct reuse.
Its pool boundary tracks collected candidates. An edit can change nvALT search results without changing the number of notes.
Deletion, replacement, and Undo also violate its append-only assumptions.
Initially, nvALT will reuse only prepared per-note text keyed by candidate revision and the current completed result.
The candidate revision covers title, tags, and body.
Query membership caches require separate fresh-search equivalence tests before adoption.

The worker design can transfer without its shell infrastructure.
One shared scheduler will serve all browser windows, with at most two concurrent worker tasks initially.
Each serial worker lane will own one reusable matcher slab. A one-worker configuration remains available for performance comparison.
Waiting browsers receive turns between work batches. Request replacement cancels obsolete scoring, sorting, and copying.
The native [worker scheduling design](https://github.com/dangduc/fzf-native/blob/4b9236e8cd1e9f9f3aaf5f2ebf83f1fc5995d38d/architecture.org#L440)
provides this fairness principle, but its fixed candidate-count budgets need adjustment.

Notes vary much more in length than completion labels.
The adapter must check cancellation between notes and bound batches by bytes and elapsed time.
Upstream's 2,048-candidate batches and checks every 256 candidates cannot establish responsive cancellation for large notes.
One matcher call remains uninterruptible. The existing large-note latency gate still applies.

The adaptation does not require `fzfa` Lisp files, an Emacs runtime, shell producers, a line reader, or producer arenas.
It also excludes history reranking, Emacs source-group ordering, and permanent polling timers.
Title-first grouping and duplicate result rows are nvALT application policy, separate from the native scorer and sorter.
Extracted native sorting code retains its GPL-3.0-or-later notices, as already specified in the search plan.

The native API will return compact ordered identifiers with retained immutable storage.
It will not copy every matching note's full text into the UI result.
Closing a browser immediately invalidates its request ownership. Workers release their snapshots after they stop, without a main-thread join.
Selection will use result-row keys containing match kind and note UUID, together with nvALT's user-intent guards.
Editing and note operations will continue to use note UUIDs. `fzfa` does not provide this document-selection policy.

Useful upstream regression examples cover [empty partial results](https://github.com/jojojames/fzfa/blob/8d4fd2cf7e58d8055bbcccbeb54c31978f9413bf/fzfa-test.el#L1597),
[nested publication](https://github.com/jojojames/fzfa/blob/8d4fd2cf7e58d8055bbcccbeb54c31978f9413bf/fzfa-test.el#L1716),
[native order preservation](https://github.com/jojojames/fzfa/blob/8d4fd2cf7e58d8055bbcccbeb54c31978f9413bf/fzfa-test.el#L2752),
and [request-ID reuse across lifetimes](https://github.com/jojojames/fzfa/blob/8d4fd2cf7e58d8055bbcccbeb54c31978f9413bf/fzfa-test.el#L4245).
nvALT tests must also cover equal-count note edits, deletion during scoring, cancellation during sorting, and two active browser queries.

The source and test definitions were inspected. The Emacs suites were not run, and this audit adds no performance claim for nvALT.
