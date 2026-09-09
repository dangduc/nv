# R1 source-highlight fix

Addresses [Dan Luu review P2](https://github.com/fastducduc/nv/pull/10#issuecomment-5599763681).
The original review evidence remains unchanged under `Tests/FuzzySearch/Review/round-1/luu`.

Literal source-range discovery now runs on the shared search worker.
It checks cancellation before and after each Cocoa substring search.
Discovery stops after 2,048 literal occurrences in parsed-term order. Overlapping ranges merge.
The editor installs at most 2,048 search-background ranges, including native fuzzy ranges.
These limits affect source decoration only. They do not exclude notes, truncate source, or change result order.

The worker compares immutable displayed and committed source before publishing ranges.
The comparison requires identical UTF-16 content. Canonically equivalent strings with different code units cannot share offsets.
Every attached editor's existing character-edit notification advances its publication generation immediately.
Completion also checks that the selected occurrence remains current.
Cancellation releases captured browser objects on main, without waiting for queued worker work.

The legacy Exact activation helper preserves its first-match caret choice and quote handling.
It now finds only the needed first occurrences. It does not allocate or install every matching source range.
Actual background decoration uses the asynchronous controller path.
That legacy caret lookup remains synchronous. Individual Cocoa comparisons and source copies also have no elapsed-time guarantee.

## Evidence

```sh
python3 Tests/FuzzySearch/HighlightBounds/run.py --negative-controls
python3 Tests/FuzzySearch/HighlightBounds/run.py --sanitize
python3 Tests/FuzzySearch/HighlightBounds/run.py --arch x86_64 --build-only
```

The probe passes 106 checks natively and under ASan/UBSan.
All six negative mutations fail: missing generation, row context, cancellation, discovery limit, editor limit, and source compatibility.
Assertions check operation bounds and behavior; timings are observations rather than CI thresholds.
The existing 135 service checks pass under sanitizers. The shared-character observer's seven checks also pass.
The Intel probe compiles. No Intel execution or complete-app UI result is claimed.

The fixture extracts the actual controller refresh, character-edit callback, and editor highlight methods.
It links the production query, service, and native matcher code.
Real NSTextStorage and NSLayoutManager objects supply temporary attributes and character notifications.
Small fixtures compare the legacy caret result against the earlier algorithm across 48 body/query/flag combinations.
Held completions test query changes, duplicate-row changes, uncommitted edits, cancellation, and browser lifetime.

The 8 MiB source contains over one million possible literal matches for `a`.
The final native run records main submission, application, and clearing costs in [native.log](native.log).
Typical recorded costs are below 1 ms for submission and clearing, and below 3 ms for application.
The initial review recorded approximately 750 ms for fresh refresh, 990 ms for replacement, and 230 ms for clearing.
A separate reference measurement still demonstrates the former source-comparison cost of approximately 37 ms.
That comparison now runs on the worker.

These are arm64 process measurements on macOS 26.5.2 with Xcode 26.6.
The fixture does not include text containers, glyph layout, windows, or painting.
Source characters and temporary syntax foreground attributes remain unchanged.
