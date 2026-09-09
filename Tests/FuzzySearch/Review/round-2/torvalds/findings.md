# Round 2: display limits and Unicode boundaries

No actionable finding emerged from this focused review. Severity: none.
The new probe passed **40,171 assertions** in both native arm64 and AddressSanitizer/UndefinedBehaviorSanitizer runs.
The Intel executable compiled and linked for macOS 10.13. No Intel executable ran.

The review used a correctness and simplicity lens inspired by Linus Torvalds. It does not represent his review or endorsement.

## Source and commands

The review began with repairs in the working tree above `a611cee399db63eb9edb0958358469c0eda30945`.
The final source comparison used HEAD `abdd49c89ddcf5123fc3249234fc01238ff4cc59`.
All recorded source hashes matched the final checkout. No recorded source changed during compilation or execution.
The result files contain exact hashes, compiler commands, output, and exit codes.

| Command | Result | Record |
| --- | --- | --- |
| `python3 Tests/FuzzySearch/Review/round-2/torvalds/run.py` | 40,171 assertions passed | [Native results](native-results.json) |
| `python3 Tests/FuzzySearch/Review/round-2/torvalds/run.py --sanitize` | 40,171 assertions passed. No sanitizer diagnostic. | [Sanitizer results](sanitize-results.json) |
| `python3 Tests/FuzzySearch/Review/round-2/torvalds/run.py --intel-compile-only` | Compile and link passed | [Intel results](intel-compile-only-results.json) |

The host used macOS 26.5.2 and Xcode 26.6.
The probe links the complete production query, corpus, service, native bridge, and vendored matcher files.
It does not substitute service callbacks or extract service methods.

## New evidence

- Occurrence caps of 0, 1, 2,047, 2,048, 2,049, and unlimited produced the expected literal ranges.
- Adjacent matches merged. Repeated terms consumed the documented occurrence budget in parsed-term order.
- Quoted colons and newlines remained literal. Canonical accent matches and partial emoji matches expanded to complete original graphemes.
- Cancellation returned no partial range list, including empty queries and a zero occurrence cap.
- All 1,024 subsets of ten specified Unicode atoms mapped to independently specified UTF-16 ranges.
- Mapping covered NFC/NFD accents, reordered combining marks, Hangul, flags, an emoji sequence, CRLF, and candidate NUL.
- Native service positions mapped into the original title, tag, and source fields with exact expected ranges.
- Source comparison rejected canonical equivalents with different UTF-16 content, reordered marks, changed line endings, and changed trailing text.
- Caller mutations after submission did not change the copied source, displayed source, query, or native range array.
- Replacement suppressed the older callback. A peer owner still completed. Invalidation suppressed pending publication.
- Native presentation output stopped at 2,048 ranges.
- A separate corpus returned all 2,053 title matches and all 2,053 fuzzy matches. The display cap did not truncate either result group.

## Limits

These new checks target display discovery, copied inputs, source compatibility, and UTF-16 mapping.
They do not repeat the broad native-order parity work from round one.
The bounded literal scan counts occurrences before overlap merging. It does not promise 2,048 distinct displayed ranges.

The probe uses Foundation without windows, text containers, or painting.
The editor cap and controller publication guards received source review only in this round.
The executions do not establish full-app notification order, frame times, or behavior on an actual macOS 10.13 system.
They cover specified Unicode atoms, not every Unicode sequence or Foundation Unicode-data version.
No allocation fault injection or elapsed-time cancellation guarantee is claimed for these new checks.

This review added only round-two evidence. It made no production changes, original-test changes, round-one changes, or commits.
