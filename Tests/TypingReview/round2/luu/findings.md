Round 2 of 3, measurement and performance perspective inspired by Dan Luu.
This is an independent review perspective, not a statement from that person.
Reviewed `5eda58bd50bdda6b31ea705ad1ce6b256ffd671a` against `8dde5e8`.

**No new evidence-backed revision request.** The round 1 dictionary-set defect is resolved.
The current publication method still has measurable whole-note scan and attribute-update costs.
The results below separate those costs from actual attribute shifts and snapshot creation.

Run from the worktree root:

```sh
python3 Tests/TypingReview/round2/luu/run.py
```

Result: exit 0, `PASS: production publication, shift, snapshot, and word-cache probes`.
The runner extracts `getWordCount:`, `snapshotForSourceAnalysis:`, and `sourceAnalysis:didFinish:` unchanged from `NVNoteEditingSession.m`.
It compiles the complete production `NVSourceAnalysis.m` and existing production link decorators.
Fixture objects supply the method environment; they do not replace the measured algorithm.
The probe attaches a real `NSLayoutManager` without a text container. It does not create a view or window.
Build products and extracted source are under `build/TypingReview/round2/luu/`.

The table reports median publication time from five fresh storage instances per case.
The 1,000-, 4,000-, and 10,000-link fixtures contain about 25,000, 100,000, and 250,000 UTF-16 units.
Every fresh link list comes from the production detector after the actual storage edit or syntax change.
Assertions check initial/final link counts, exact final ranges and targets, and edit notifications.

| Actual operation before publication | 1,000 links | 4,000 links | 10,000 links |
| --- | ---: | ---: | ---: |
| Insert in final plain line; unchanged links | 0.655 ms | 3.989 ms | 13.935 ms |
| Insert at start; all old attributes shift through TextKit | 0.650 ms | 3.960 ms | 13.835 ms |
| Replace one character in one link target | 0.679 ms | 4.040 ms | 14.080 ms |
| Replace one character in every link target in one edit batch | 3.543 ms | 18.229 ms | 71.462 ms |
| Change Plain Text to Org; remove all wiki targets | 1.960 ms | 12.474 ms | 56.476 ms |
| Change Org to Plain Text; add all wiki targets | 1.726 ms | 5.780 ms | 11.295 ms |

Both the final-line edit and the start-of-note insertion cause **zero publication edit notifications** in all five trials.
TextKit shifts existing attributes before analysis publishes. The new ranges already match those shifted attributes.
This test therefore does not supply artificial shifted result arrays against unshifted storage.
Every case that changes attributes produces one coalesced edit notification per publication.

The 10,000-link bulk target-change maximum was 76.705 ms; syntax removal reached 59.163 ms.
These are measured main-thread method durations, with extraction and edit setup excluded.
They show that the ordered merge does not bound all attribute work or eliminate full-note scans.
They do not establish a new regression against the old bulk-edit or whole-note syntax-change path.
No baseline bulk-operation control was run, and these dense fixtures are not average notes.
The 4,000-link unchanged case is about 4 ms here, compared with the round 1 defect's roughly 2.85 seconds.
Those separate runs had different layout-manager setups; the comparison establishes removal of the large pathological cost, not a precise speedup ratio.

Snapshot checks use repeated text containing ASCII, accented characters, and Japanese characters.
Each copied snapshot remains alive while the next real character replacement occurs.
An assertion verifies that the snapshot retains its old character after storage mutation.
A separate loop measures the same replacements without a retained analysis snapshot.
The table reports medians over 31 samples, without subtracting timer overhead.

| UTF-16 units | Snapshot method | Snapshot maximum | Edit holding snapshot | Edit without snapshot |
| --- | ---: | ---: | ---: | ---: |
| 100,008 | 0.001 ms | 0.012 ms | 3.598 ms | 3.477 ms |
| 1,000,008 | 0.001 ms | 0.005 ms | 3.479 ms | 3.450 ms |
| 4,000,008 | 0.001 ms | 0.005 ms | 3.483 ms | 3.494 ms |

This fixture does not show a size-dependent main-thread copy penalty, either in snapshot creation or in the next edit.
The microsecond-level creation measurements are close to the timing overhead and are not a portable latency guarantee.

The exact `NVSourceWordCount` helper took 21.973 ms for 100,008 units / 20,835 words and 219.821 ms for 1,000,008 units / 208,335 words.
The probe calls this helper synchronously to isolate its duration; production calls it on the analysis worker.
Publishing each precomputed count through the production session method, notifying one fixture observer, and reading the production cache averaged 0.000472 and 0.000468 ms over 1,000 calls.
Every notification read the expected cached count. This does not time browser label formatting, observer re-registration, or drawing.
No new worker-cancellation finding is inferred from the helper duration.

Saved results use macOS 26.5.2, Apple clang 21, `-O2`, and the Intel target under Rosetta.
`output.txt` contains the final complete run; `environment.json` records the reviewed commit, production source hash, compiler, and command.
An initial prototype with unbatched bulk-edit setup exceeded the 110-second process bound and produced no retained timing data.
The final probe batches bulk replacements into one storage transaction and completes within that bound.
These probes do not establish visible frame timing, macOS 13.7.8 compatibility, or total application CPU changes.
The root typing benchmark remains the evidence for whole-application dispatch and deferred CPU results.
