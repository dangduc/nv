Round 3 review: metadata cost with two browser windows

This AI review applies a Dan Luu-inspired measurement perspective. Dan Luu did not participate.

No new actionable finding arose from this bounded experiment. The probe passed 155 checks. The deferred refresh cost increased with the library size, while both browser queries and selections remained correct.

The reviewed production source is `12936fed78e1d98ac646bb88b51e009609ad505e`. The evidence-only HEAD is `0afeb03837b94c1a16da211a79c9eaf8dfe51183`. The host used macOS 13.7.8 (22H730), Xcode 15.2 (15C500b), and an x86_64 app under Rosetta.

The source app is `build/DerivedData/Build/Products/Development/nvALT.app`. Its executable SHA-256 is `f9d0a299a852c80fae0574722776d5e732031fec6f4c328861e57d74d9d00228`.

The experiment used 1,000 notes, then extended the same library to 10,000 notes. Each note had a short body. Two windows used the default Date Modified sort and enabled title completion.

The primary query, `bench`, matched every note. The peer query, `watch`, matched a sentinel note and conditionally matched the edited note's tag. The primary window selected the edited note. The peer selected the sentinel. Tag changes therefore changed the peer result count between one and two.

Each size included one warmup and five measured commits for each metadata type. The probe opened a native header field, inserted its replacement value, and dispatched the production Return delegate method. It measured two operations separately:

- Return dispatch: elapsed time inside the Return delegate call.
- Deferred refresh: elapsed time inside the scheduled `refreshBrowsers` call, including both browser sessions.

| Notes | Metadata | Return dispatch median, range (ms) | Deferred refresh median, range (ms) |
| --- | --- | --- | --- |
| 1,000 | Title | 5.958, 3.125–6.909 | 4.631, 2.855–5.795 |
| 1,000 | Tags | 2.645, 1.840–5.361 | 3.367, 3.121–4.150 |
| 10,000 | Title | 15.255, 11.732–15.920 | 37.885, 36.330–39.823 |
| 10,000 | Tags | 2.474, 1.809–2.644 | 41.442, 36.330–43.334 |

Each measured commit produced exactly one deferred refresh. No refresh ran inside the Return dispatch. A second event-loop drain added no refresh calls. The timing wrapper called the original production method. It did not replace filtering, sorting, callbacks, or scheduling.

Expected behavior: the note contains the committed value, and each browser retains its query and selected note. Tag commits must add or remove the edited note from the peer results. Every measured commit satisfied these assertions. Body text and the final 10,000-note count also remained intact.

The source explains why library size affects deferred work. `NVApplicationController.m:231-236` schedules one callback for all browsers. `NVBrowserSession.m:168-175` invalidates the candidate cache. `NVBrowserSession.m:145-165` then scans the library, sorts matches, updates the data source, and clears cached previews.

The browser-session implementation has no diff between `116daff` and the reviewed production source. Title commits also rebuild title-prefix connections at `NotationController.m:950`. That operation sorts the library at `NotationController.m:783-817`. This experiment does not isolate the cost of each internal operation.

The exact command ran from the repository root:

```sh
python3 Tests/NativeUIReview/round3/luu/run.py > Tests/NativeUIReview/round3/luu/current.txt 2>&1
```

The command exited `0`. Its final output contains `ROUND3 LUU METADATA COST PASSED (155 checks)`. `current.txt` preserves all sample values, timing summaries, callback counts, fixture details, and assertion output.

The runner acquires `build/pr-review/gui.lock` and uses a copied app. It creates temporary notes, support files, and a unique defaults domain. It omits delayed sync actions and external editor initialization. The app process has a 90-second timeout. The tool call requested elevated execution for Rosetta.

Native activation, the key window, and both explicit color schemes passed their fixture checks. The run required no fixture correction or production change.

These values describe one process, one host, two short queries, short note bodies, and five samples per case. The run processed 1,000 notes before 10,000 notes. It did not randomize case order or compare another app revision.

The measurements exclude field insertion, event-loop waiting, final screen display, and library creation. They do not establish key-to-display latency, memory use, or a worst-case bound. A 36–43 ms deferred refresh is measurable main-thread work. These samples alone do not establish a new regression or an acceptable latency limit.
