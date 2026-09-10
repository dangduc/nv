Review round 1 of 3, measurement/performance perspective inspired by Dan Luu.
This is an independent review perspective, not a statement from that person.
Reviewed candidate `b3c2162b9adea5e1c2819f7372ff0f7e7986a64a` against `8dde5e8`.

**[P1] Replace dictionary sets in main-thread link publication.**

Affected lines: `Sources/Editor/NVNoteEditingSession.m:221–225`.
Trigger: type in a short line after hundreds or thousands of existing wiki links or web URLs, then allow analysis to publish.
The edit need not change any link. This includes a large imported reference list or bookmark note.

Each link record is a two-entry `NSDictionary` containing a range and URL.
Every record in this probe has hash value `2`, despite distinct ranges and targets.
Both `setWithArray:` calls and the following membership tests therefore perform quadratic comparison work on main.
The method runs even when all link attributes already match the result.
The previous edit handler decorated only the edited line.

Reproduction command from the worktree root:

```sh
python3 Tests/TypingReview/round1/luu/run.py
```

Result: exit 0, `PASS: production publication scaling and canceled-job contention probes`.
The runner compiles the complete production `NVSourceAnalysis.m`, production link methods, and the exact publication method extracted from `NVNoteEditingSession.m`.
The fixture supplies storage, generation, and syntax to that unmodified publication method.
After initial publication, it inserts `x` in the final plain-text line, advances the generation, and publishes unchanged link ranges.
No layout manager is attached, so these timings exclude layout and drawing costs.

| Fixture | UTF-16 length | Link count | Production extraction | Initial publication | Publication after plain-line edit | Previous line-decoration operations |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Wiki | 12,529 | 500 | 3.646 ms | 12.241 ms | 45.466 ms | 0.090 ms |
| Wiki | 25,029 | 1,000 | 7.287 ms | 46.366 ms | 182.696 ms | 0.155 ms |
| Wiki | 50,029 | 2,000 | 14.577 ms | 183.216 ms | 719.788 ms | 0.193 ms |
| Wiki | 100,029 | 4,000 | 29.138 ms | 719.019 ms | 2,848.058 ms | 0.208 ms |
| Web URLs | 88,029 | 2,000 | 51.596 ms | 183.527 ms | 715.369 ms | 0.164 ms |

Doubling the link count approximately quadruples publication time.
An 88 KB URL list incurs about 715 ms of main-thread work after an unrelated one-character edit.
The 100 KB wiki case incurs about 2.85 seconds.
These fixtures emphasize link density; they do not represent the average note.
The regression also appears at 500 links in a 12.5 KB wiki note, where publication takes about 45 ms.

Suggested fix: merge the already ordered old and new link-run arrays by range and compare targets directly.
Collect removals and additions during the merge, then apply every removal before any addition.
This preserves overlapping-range behavior without relying on `NSDictionary` or `NSValue` hashes.
Add a scaling check with unchanged links, plus changed, overlapping, added, and removed links.

The measurements above are one saved run on macOS 26.5.2, compiled for x86_64 under Rosetta with Apple clang 21 and `-O2`.
Two earlier runs independently showed the same quadratic curve; they are not pooled into the table.
The extraction column times the production helper synchronously in the headless process to isolate its cost.
Production calls that helper on its worker.
The final column times only the previous remove-and-redecorate-line operations, not a complete old app keystroke.
Raw output and the exact compiler command are in `output.txt` and `environment.json`.
This probe does not establish frame timing or behavior on macOS 13.7.8.

**Worker contention observation; no separate revision request.**

The same executable observes the real production decorator without inserting a delay or gate.
After a 500,029-character / 20,000-link job enters decoration, it closes that analysis object and requests a small note on another analysis object.
The closed helper continues for 148.311 ms because cancellation is checked between whole helpers, at `NVSourceAnalysis.m:92–95`.
The small request publishes after 166.490 ms, compared with 63.863 ms on an idle queue.
The closed job never publishes, and the small job eventually completes.
This establishes queue coupling but does not independently establish an unacceptable responsiveness threshold or a regression against the synchronous baseline.

The existing production benchmark uses plain text without links, so it cannot detect the publication regression above.
Its distinction between synchronous key dispatch, deferred main-thread CPU, and visible stutter is accurate.
This review found no additional evidence-backed performance defect in the list-refresh changes.
