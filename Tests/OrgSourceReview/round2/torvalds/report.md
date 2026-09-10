# Org source review, round 2: native correctness and portability

This review uses a Linus Torvalds-inspired perspective on native boundaries, straightforward state handling, and dependency costs.
It does not represent his views.

Reviewed commit: `4dab02a9020ff8f76cceeffc75a001927255a17e`.
Base: `f3a8abb2b7942d06ec33af64b4946cfd1b6db163`.

## Result

No new actionable findings in the reviewed scope.
The local scanner patch addresses the first-round serialization finding.

The encoder checks the complete representation before it writes a normal state.
Counts and values use explicit widths and byte order.
The decoder validates the complete input before it changes the stacks.
The failure flag survives scanner restoration within a parse.
The highlighter resets that flag before its synchronous Org parse and reads it immediately afterward.
A failed parse clears its tree and parser state.

Relevant production locations:

- `ThirdParty/TreeSitter/org/src/scanner.c:80`: thread-local failure bridge.
- `ThirdParty/TreeSitter/org/src/scanner.c:126`: complete encoding validation.
- `ThirdParty/TreeSitter/org/src/scanner.c:156`: complete decoding validation.
- `Sources/Editor/NVSourceHighlighter.m:317`: bridge reset, read, and parser cleanup.

## New executable evidence

Run `python3 Tests/OrgSourceReview/round2/torvalds/run.py` from the repository.

`codec.c` builds only the patched scanner.
It checks 360 legal states against an independent expected-byte encoder.
These states vary all bullet values, stack depths, values above one byte, and the math flag.
Each state also checks exact write length, restored values, canonical re-encoding, and object reuse after empty restoration.
The expected-byte encoder uses division and remainder and does not call production encoding helpers.

`bridge.m` compiles the production highlighter and all production grammar wrappers.
Four concurrent workers each reuse two independent parser sessions.
Each worker parses ordinary Org text and injects the patched codec's documented failure marker after selected successful parses.
This tests the adapter's decision separately from the parser's recognition of document text.

The bridge checks these outcomes:

- The affected session returns no captures for a failed parse.
- Another session on the same worker continues to return fresh-equivalent captures.
- The affected session recovers on its next request.
- An intervening cancellation returns no capture result and does not damage later requests.

| Build | Codec checks | Bridge checks |
|---|---:|---:|
| Intel, signed `char`, macOS 10.13 target | 5,040 | 480 |
| Intel, unsigned `char`, macOS 10.13 target | 5,040 | Not run |
| arm64, macOS 11.0 target | 5,040 | 480 |
| arm64 with AddressSanitizer and UndefinedBehaviorSanitizer | 5,040 | 480 |

All checks passed. The sanitized executions reported no errors.
The Intel bridge executable records macOS 10.13 as its deployment target.
The production highlighter also compiled with unguarded-availability diagnostics treated as errors.

## Package review

All 76 vendored file sizes and SHA-256 hashes match the manifest.
Their total byte count matches `vendored_bytes`.
The scanner is the only modified file among the six files copied from the pinned Org revision.
The manifest identifies that modification and records the local patch document.
The distribution notices include the complete Org MIT license and describe the local scanner modification.

The checked upstream revision is `f15da8e8fcb3a2d764c7092ae6ba4dc87d3b3093`.
The comparison reads the existing local investigation checkout; it does not download or execute upstream build scripts.

## Limits

These checks do not prove execution on an actual macOS 10.13 installation.
The codec cases cover legal, modest states; separate fixed-scanner tests cover capacity and rejected-state contracts.
This review does not run an unpatched scanner or construct a crashing note.
The injected marker proves adapter fallback behavior, not that every document follows the intended grammar.
The native tests do not exercise TextKit display, Undo, window routing, or application lifecycle.
The root task validates the complete app separately.

Host: macOS 26.5.2, Xcode 26.6, build `17F113`.
Evidence: `codec.c`, `bridge.m`, `run.py`, `output.txt`, and `metadata.json` in this directory.
