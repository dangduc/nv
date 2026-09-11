P3: Avoid redundant composed-character queries for separators with strictly printable ASCII neighbors.
Location: `Sources/Editor/LinkingEditor.m:315` at frozen commit `2ea92180939a3e51df8fe867ad548140ed455868`.
This is a nonblocking performance recommendation supported by an unshipped experiment.
This review uses a performance perspective inspired by Dan Luu. Dan Luu did not conduct this review.

The candidate adds a material cost to complete layout of large ASCII paragraphs.
A start insertion/deletion pair in a 256K paragraph took 113.411 milliseconds at the base and 131.697 milliseconds at the candidate.
The added 18.286 milliseconds includes 13.586 milliseconds of additional delegate time. The candidate made 89,875 composed-character queries during that pair.
Both versions generated the same 524,289 glyphs and processed the same 524,289 typesetter snapshot units.
Thus, this delta accompanies existing paragraph work. The change does not expand that work in these cases.

A conservative shortcut can skip the composed query when both adjacent UTF-16 units are U+0021 through U+007E.
Those printable ASCII neighbors establish a separate U+0020 cluster. The other existing eligibility checks remain necessary.
For any neighbor outside that range, the original composed-character guard must remain.

The probe-only variant produced the following results on one 256K ASCII paragraph:

| Operation | Frozen candidate | ASCII experiment | Saved |
| --- | ---: | ---: | ---: |
| Initial layout | 66.826 ms | 62.418 ms | 4.408 ms |
| Start edit pair | 128.196 ms | 118.764 ms | 9.432 ms |
| Delegate within start pair | 18.315 ms | 9.436 ms | 8.879 ms |
| Composed queries within start pair | 89,875 | 0 | 89,875 |

The experiment retained identical line boundaries, glyph properties, and restored source for the large fixture.
Fourteen additional controls covered combining marks, variation selectors, ZWJ, emoji, CJK, Arabic prepend, repeated spaces, indentation, trailing spaces, and controls.
All controls retained identical layout and properties. Nine composed queries still ran through the fallback path.
This experiment does not replace the full separator correctness suite before any production optimization.

The main comparison used the frozen candidate against `75d6f42`. Production code was unchanged since round 1.
Each edit pair inserts one space after a separator, requests complete layout, deletes that space, and requests complete layout again.
The short-paragraph fixtures contain 256 UTF-16 units per paragraph and match the total size of the single-paragraph fixtures.

| Document | Initial base → candidate | Start pair base → candidate | End pair base → candidate |
| --- | ---: | ---: | ---: |
| 128K, one paragraph | 28.899 → 33.744 ms | 55.456 → 65.264 ms | 0.349 → 0.320 ms |
| 128K, short paragraphs | 43.442 → 48.427 ms | 0.307 → 0.338 ms | 0.303 → 0.300 ms |
| 256K, one paragraph | 59.188 → 69.635 ms | 113.411 → 131.697 ms | 0.412 → 0.435 ms |
| 256K, short paragraphs | 88.972 → 99.937 ms | 0.388 → 0.490 ms | 0.434 → 0.495 ms |

Here, 128K and 256K mean 131,072 and 262,144 UTF-16 units.
The large initial-layout increases are material for both paragraph structures. They follow the total generated glyph count.
Localized edits show the existing paragraph dependence:

| 256K document and edit pair | Generated glyphs, both versions | Typesetter snapshot units, both | Candidate composed queries |
| --- | ---: | ---: | ---: |
| One paragraph, start | 524,289 | 524,289 | 89,875 |
| One paragraph, end | 129 | 129 | 19 |
| Short paragraphs, start | 513 | 511 | 85 |
| Short paragraphs, end | 199 | 197 | 31 |

Each pair produced two storage-edit callbacks with one invalidated source unit in total.
That storage notification range is not the expanded glyph-generation range. The generated-glyph counts expose the larger work.
All twelve operation comparisons had equal invalidation, glyph-generation, and typesetter work counts between the two production variants.
The candidate also reduced explicit allocation during the 256K start pair from 512 buffers and 4,194,304 bytes to two buffers and 16,384 bytes.
These allocation counts cover delegate property buffers, not Foundation internals or total memory.

The runner extracts both exact production delegates and the unchanged `NVSourceTypesetter` from Git.
It reuses the committed round-one observer and text-system scaffolding, with new fixtures and a storage-edit observer.
The timing build uses unmodified delegate methods. A separate build counts composed queries, buffers, glyph callbacks, and selected Core Text work.
Both builds passed source-preservation and restored-layout checks.

The main medians use four retained trials after one discarded trial, with alternating variant order.
The experiment uses two retained trials after one discarded trial. Its timings include instrumentation and require comparison within that experiment.
The fixture uses a 544-point container, 16-point Menlo, `-O2`, manual memory management, and x86_64 through Rosetta.
The host ran macOS 26.5.2 and Xcode 26.6 on arm64. Host load was not controlled.
No GUI, text view, user notes, or production edits participated.
The measurements exclude event dispatch, drawing, source analysis, undo, and model updates. They do not establish full-application keystroke latency.

To reproduce the main comparison, run this command from the repository root:

```sh
python3 Tests/WrappedSeparatorReview/round2/luu/run.py
```

To reproduce the unshipped shortcut experiment, run this command:

```sh
python3 Tests/WrappedSeparatorReview/round2/luu/experiment.py
```

`results.json` contains the main samples, medians, counts, and environment.
`experiment-results.json` contains the separate experimental samples and controls. The logs record successful completion.
All retained evidence, code, and this report fit within 150 KiB.
