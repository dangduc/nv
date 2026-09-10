# Round 1: visual correctness and forgotten user paths

This review uses a contrarian perspective. It tests whether the crash fix causes incorrect display behavior. It does not represent a real person's review.

No actionable finding was found in the tested paths.

The probe compares the exact current drawing delegate with the delegate from base `54ce3b8`. It permits one difference: invalidated search backgrounds must disappear. All other attributes and effective ranges must match the base behavior.

The current production files match `c2209e2`. The run ended at `714d586`, which adds review evidence. All four production file hashes remained unchanged during execution. The complete hashes are in `manifest.json`.

## Executable evidence

Run from the repository root:

```sh
python3 Tests/SourceBackspaceReview/round1/contrarian-b/run.py
```

The Intel probe ran through Rosetta on macOS 26.5.2. It compiled with warnings treated as errors.

The probe passed **39,819 assertions** from 7,680 attribute combinations and native temporary-storage checks. The combinations cover:

- Pending and current search backgrounds, present and absent backgrounds, and light and dark source colors.
- Screen and offscreen delegate calls, valid and out-of-range character indices, and null input attributes.
- Four capture categories, valid and invalid syntax revisions, and capture tokens attached to a different storage.
- Links, marked ranges that cover part or all of the source, and unmarked text.
- Foreground colors, underline attributes, unrelated markers, and link and marked-text effective ranges.

The real `NSTextStorage` and `NSLayoutManager` checks confirm that invalidation leaves stored backgrounds intact until deferred cleanup. Both delegate output paths suppress those backgrounds during that interval. Cleanup preserves syntax markers and underline attributes. A fresh background survives cancellation of the old callback and coexists with the link foreground color.

Five deliberate defects fail the same checks:

| Negative control | Failed assertions |
| --- | ---: |
| Remove background suppression | 1,922 |
| Discard unrelated temporary attributes | 5,346 |
| Suppress valid fresh backgrounds | 1,921 |
| Suppress backgrounds only for screen output | 961 |
| Ignore marked-text foreground ownership | 3,200 |

`production.txt`, the five negative-control outputs, and `manifest.json` preserve the results. The manifest identifies the exact extracted methods and generated source hashes.

## Limits

This probe evaluates delegate dictionaries and AppKit attribute storage. It does not render pixels, create a browser, or operate an input method. The adapter supplies marked ranges, appearance colors, and link preferences. It extracts the production capture-revision helper and configures its tokens directly.

The probe does not establish whether AppKit presents a frame during every edit notification. It does not test printing UI, custom IME background attributes, or macOS 13.7.8. Existing offscreen treatment of syntax markers is unchanged by the fix; this comparison does not establish its suitability for printing.

The matrix establishes that the new suppression step preserves the existing syntax, link, range, and marked-foreground behavior for the supplied inputs. It supplements the full-app deletion suite; it does not replace it.
