# Round 1 performance correction

Character wrapping removes the measured long-space reflow slowdown in the copied app.
The short-note key probe shows similar dispatch cost before and after this correction.

Environment: macOS 26.5.2 (25F84), Xcode 26.6 (17F113), Intel apps under Rosetta.

## Actual app measurements

Each app uses temporary notes, a unique preference domain, and the shared GUI lock.
The probe measures three width changes for each note size at Menlo 12 in Plain Text mode.
The window enforces its minimum size, so the actual text container changes from 704 to 464 points.
Each measurement includes the window size change and complete resulting editor layout.

| Contiguous spaces | Native baseline | Original glyph adjustment | Character-wrapping correction |
| --- | ---: | ---: | ---: |
| 4,096 | 9.79 ms | 8.03 ms | 6.95 ms |
| 8,192 | 11.79 ms | 10.49 ms | 6.82 ms |
| 16,384 | 18.49 ms | 22.59 ms | 8.09 ms |
| 32,768 | 29.85 ms | 64.00 ms | 10.30 ms |

The values are medians of three trials.
At 32,768 spaces, both adjusted apps produce 529 lines. The baseline still collapses the spaces onto one line.
This control separates the correction from a return to collapsed whitespace.
Every reflow preserves source characters, the committed note model, and the logical selection.

The original P3 probe used a standalone 160-point container.
Its approximately 168 ms result is not directly comparable with this app's 464-point minimum container.
The app measurement establishes that the correction also removes the observed cost at a supported window size.

The short-note probe sends 90 actual Space or `k` key events per trial, with `isARepeat` after the first event.
Three trials check the exact live source, committed model, and logical caret after every key.

| Median per 90 keys | Native baseline | Original glyph adjustment | Character-wrapping correction |
| --- | ---: | ---: | ---: |
| Event dispatch total | 376.77 ms | 371.41 ms | 379.49 ms |
| Main-thread CPU | 260.70 ms | 258.73 ms | 269.11 ms |

The corrected dispatch total is approximately 2.2% greater than the original adjustment in this small sample.
Main-thread CPU is approximately 4.0% greater.
CPU includes probe checks, logging, drawing, and deferred work between events.
These observations support a performance sanity check; they do not establish frame smoothness or a small statistically significant regression.

All three apps pass 586 checks each, including 270 native key events per app.

## Shared paragraph style

The next correction shares one immutable paragraph style through `dispatch_once`.
The extracted production getter produces one distinct live style across 10,000 calls.
A control restores the earlier per-call style creation and produces 10,000 distinct live styles.
All styles use character wrapping.

The measured style object allocations total 96 bytes with the shared style and 960,000 bytes with the control.
These values exclude dictionaries, retained tab arrays, allocator metadata, and temporary mutable copies.
The inherited getter retains old attribute dictionaries. This probe leaves that behavior unchanged.
Sharing the style avoids adding one retained style object to each retained dictionary.

The style probe uses the production getter with fixed palette and font dependencies.
Its font object is a placeholder because this getter only stores that object; it does not measure or draw text.
It creates no application or window and loads no preferences.

## Build identities and limits

The app benchmark uses the first character-wrapping build, before the shared-style allocation change.
Its binary SHA-256 is `ce1abfa2bcda08415d726352a2575412bfabb2e9f4c640a5519db7e1276beacc`.
The shared-style probe uses the later production getter directly.
The allocation change preserves the paragraph policy; this report does not claim a second app benchmark after that change.

The original adjustment comes from `build/WhitespaceWrapping/nvALT-Space-Wrap.zip`.
Its binary SHA-256 is `6682e85cff4069c18b65ef9989830de2b72c3513240302a197395551d53d7d0c`.
The native baseline binary SHA-256 is `d2fc91aab87fbb3937073e11908832d177559761e46237ecd597a3bd9ca5ec80`.

Run `python3 Tests/WhitespaceWrapReview/fixes/round1/perf/run.py` for the copied-app measurements.
Run `python3 Tests/WhitespaceWrapReview/fixes/round1/perf/run-style.py` for the allocation comparison.

`results.json` records the app identities and every measured trial.
`style-results.json` records the allocation counts. Logs and build products remain under ignored `build/WhitespaceWrapReview/fixes/round1/perf`.
The probes do not establish macOS 13 performance, all fonts, or physical held-key frame timing.
