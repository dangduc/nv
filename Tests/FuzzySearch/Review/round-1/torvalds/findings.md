# Round 1: correctness and simplicity review

No actionable findings in the reviewed C bridge, native pattern extraction, native ranking extraction, or normalization boundary.
Severity: none. This conclusion applies to the source hashes and checks recorded here.

The review used a correctness and simplicity lens inspired by Linus Torvalds. It does not represent his review or endorsement.

## Source state

- Branch: `codex/fuzzy-search-plan`.
- Initial HEAD: `a9539cca76e260546310caa4918d018f802b064b`.
- Final HEAD: `c7e61cbd5cd863cc285d09614b4cd3a2b18e11e7`.
- The initial checkout contained the proposed changes. Another agent committed those changes during this review.
- Every recorded source hash matched the final checkout. The review made no production changes or original test changes.
- [The arm64 manifest](arm64-sanitize-sources.json) and [the Intel manifest](intel-compile-only-sources.json) contain the source hashes.

## Executable evidence

From the repository directory, run these commands:

```sh
python3 Tests/FuzzySearch/Review/round-1/torvalds/run.py
python3 Tests/FuzzySearch/Review/round-1/torvalds/run.py --intel-compile-only
python3 Tests/FuzzySearch/Core/run.py --sanitize
```

The independent probe passed **431,292 assertions** with arm64 AddressSanitizer and UndefinedBehaviorSanitizer. [The full log](arm64-sanitize.log) contains the commands and results.

- 1,500 generated corpora covered 48,000 independent membership and position comparisons.
- The membership oracle uses contiguous or subsequence comparisons. It imports no production matcher helper.
- Inputs included literal operator punctuation, spaces, tabs, newlines, mixed ASCII case, and candidate NUL bytes.
- 300 generated Unicode corpora matched the independent upstream reference for complete order, public score, rank score, and trimmed length.
- NFC checks covered accent composition, Hangul composition, canonical mark order, and normalized codepoint offsets.
- Lifecycle checks covered copied terms, serial engine migration, early finish, repeated finish, and cancellation after one scored candidate.
- Limit checks covered the maximum query length, rank saturation, invalid candidate and collection sizes, and engine recovery.
- The invalid-candidate check included one earlier match. The error returned no partial result.

The existing core sanitizer suite also passed **23,531 checks**. Its fault sweeps covered 20 encountered parser, scorer, position, and slab allocation sites.
The same suite checked complete ordering through the allocation-free heap fallback.

The Intel build compiled and linked with deployment target 10.13. [The Intel log](intel-compile-only.log) records this result.
No Intel executable was launched. The host used macOS 26.5.2, Xcode 26.6, and Apple Clang 21.0.0.

## Review observations and limits

`NVFZF.c` validates aggregate term bytes before allocation. Collection bounds protect the match-buffer multiplications.
The job owns its copied pattern and match buffer. The candidate storage and cancellation token remain borrowed under the documented lifetime contract.
Candidate compaction preserves producer order. Finalization performs one complete native sort, then copies the result.

The C bridge intentionally leaves canonical normalization to its caller. The normalization checks use the same vendored utf8proc flags as `NVSearchCanonicalUTF8`.
These checks do not establish application UTF-16 highlight ranges or title-row publication behavior.

The review did not allocate a valid two-gigabyte candidate or a collection near `UINT32_MAX` entries.
The allocation sweeps cover encountered sites, not every possible dependency allocation path.
Intel runtime behavior, macOS 10.13 runtime behavior, and complete desktop publication remain untested by this review.
The review does not change the documented performance or cancellation limits.

## Review source hashes

| File | SHA-256 |
| --- | --- |
| `probe.c` | `13d39bb3b7b9caa5309386304cd7a7d9dbd1ee1bec7865129969a50bf6cdaa77` |
| `run.py` | `9f04c5b11a9030f7a93e6468f737d26af462f7c9e268eaae7784756a674ea3e4` |
| `Core/UpstreamReference.inc` | `9cc002f2c21eb364fa080e09c3be5f58ce85b3c878d16a1e42cb03ac3cb4d4fa` |
| `Core/reference_wrapper.inc` | `685ad65eb6b05043405df7f75afddb2d8e4cb3c8fe2752f4f59946fb760c5b82` |
