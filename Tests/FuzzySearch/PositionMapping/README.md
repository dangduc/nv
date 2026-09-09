# Position mapping fairness

This suite covers the [round-two scheduling finding](https://github.com/fastducduc/nv/pull/10#issuecomment-5600400103).
The service now resumes position mapping between worker queue turns.
Each batch visits complete composed sequences, with a 4 ms time budget and a maximum of 4,096 sequences.
The time check occurs every 64 sequences.
The cursor retains the original UTF-16 offset, NFC scalar offset, and native position index.
The request owns all native offsets until mapping completes or cancellation destroys the request.
Adjacent ranges coalesce across batch boundaries.
The change does not alter native matching, scoring, result order, or position counts.

Run the maintained fixture from the repository root:

```sh
python3 Tests/FuzzySearch/PositionMapping/run.py
python3 Tests/FuzzySearch/PositionMapping/run.py --sanitize
python3 Tests/FuzzySearch/PositionMapping/run.py --arch x86_64 --build-only
```

The `--build-only` option compiles and links without starting the binary.
The normal fixture uses no window, application library, personal note, or preference domain.

## Correctness and scheduling

Fifty parity cases compare the production batch mapper with an independent scalar-to-range oracle.
The oracle first assigns each normalized scalar its original composed-character range.
It then looks up the requested scalar positions without using the production scan cursor.
Cases include decomposed accents, Hangul, canonical reordering, embedded NUL, flags, emoji modifiers, ZWJ sequences, and CRLF.
Mixed Unicode sequences cross the 4,096-sequence boundary at four different offsets.
A sparse case retains 10,000 disjoint ranges, which exceeds the separate display cap.

Six actual-service cases gate the shared worker before submitting requests.
A long position request enters first, followed by another owner's complete query.
The peer query must publish before mapping completes.
This assertion checks publication order, with no millisecond threshold.
Two cases cancel positions between batches and require no position callback after the worker drains.

The negative control removes both batch limits from a generated service copy:

```sh
python3 Tests/FuzzySearch/PositionMapping/run.py --mutation no-yield
```

Expected result: exit 1 at `queued peer query publishes before long mapping finishes`.
Production files remain unchanged by the control.

## Recorded measurements

The native and sanitizer fixtures passed without diagnostics.
The native run passed 277,839 checks, and the sanitizer run passed 277,844 checks.
The count varies because timed batches each perform a status assertion.
The no-yield control failed at the expected scheduling assertion.
The existing service suite passed 135 checks in each configuration.
The lifecycle suite passed 236 checks in each configuration.

The table shows one native observation on Apple M3, macOS 26.5.2, and Xcode 26.6, using arm64 `-O2`.
The fixture appends `needle` after the stated prefix.
The decomposed prefix repeats `e` plus combining acute, so its UTF-8 length exceeds its UTF-16 length.

| Prefix | Peer alone | Native positions | Peer behind positions | Complete position delivery |
| --- | ---: | ---: | ---: | ---: |
| 4 MiB ASCII | 0.540 ms | 14.623 ms | 15.793 ms | 776.991 ms |
| 4 Mi UTF-16 units, decomposed | 6.334 ms | 98.894 ms | 107.168 ms | 1006.931 ms |

The original review measured 744.273–744.373 ms of peer delay for the 4 MiB ASCII case.
The new observation preserves the exact final `{4194304, 6}` source range.
The full mapping cost remains, but unrelated queries can run between batches.
The Unicode observation exposes a remaining native extraction delay.

`native-results.json`, `sanitize-results.json`, and `no-yield-results.json` record outputs, source hashes, compiler, and operating system.
The runner copies the service before compilation and adds clocks around its unchanged native-position call.
It extracts the batch primitive from that production source for the direct parity fixture.

These measurements are controlled fixtures, not typical-note latency estimates.
Native position extraction remains one uninterruptible matcher call.
One unusually long composed sequence can also exceed the mapping time budget.
This change does not establish a hard latency bound or solve the corpus scoring performance target.
