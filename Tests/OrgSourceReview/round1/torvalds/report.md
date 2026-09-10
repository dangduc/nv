# Org source review, round 1: native correctness and packaging

This review uses a Linus Torvalds-inspired perspective on straightforward code, native boundaries, and dependency costs. It does not represent his views.

Reviewed commit: `decc6788e1a746b5425f3cd248cd93071c98b8b2`.
Base: `f3a8abb2b7942d06ec33af64b4946cfd1b6db163`.

## Finding

### P1: Bound the complete scanner state before serialization

Location: `ThirdParty/TreeSitter/org/src/scanner.c:111`.

The new dependency does not preserve the Tree-sitter serialization-buffer contract for all scanner states.
Each stack-copy loop permits the write index to reach the buffer capacity.
The final math-state write then uses that index without a capacity check.
The runtime checks the returned length only after the serializer returns.
The existing source-length and analysis-time limits do not enforce this separate buffer contract.

The same format has inconsistent counts and widths.
The header clamps the indentation count, but the copy loops use the original stack lengths.
The serializer also stores `int16_t` indentation and heading values in individual `char` fields.
The decoder uses the count before it checks the complete payload length.
These operations can lose scanner state or read outside the stated payload.

This finding comes from source inspection, not a crash reproduction.
The review did not construct a note that reaches the unsafe boundary.
The native evidence below exercises ordinary documents and shows that this scanner is the one compiled into the feature.

The fix needs a complete size calculation before the first write.
An explicit format must preserve counts, value widths, and the math flag.
The decoder must check the complete header and payload before it reads stack values.
Unsupported state must trigger plain-source fallback, without a partial state that the adapter accepts as valid.
Any local patch also needs an updated manifest and a documented difference from the pinned upstream revision.

## Integration outline for the fix

The scanner can use explicit fixed-width counts and values for all three stacks.
An invalid-state marker can represent an unsupported state without exceeding the buffer.
A failure latch must survive subsequent scanner restoration during the same parse.

The native Tree-sitter API does not expose the scanner payload through `TSParser`.
A narrow thread-local Org failure latch can bridge this boundary without changes to the generic runtime.
The adapter can reset that latch immediately before its synchronous Org parse and read it immediately afterward.
On failure, it can discard the tree, clear parser state, and return the existing plain-source fallback.
A process-wide latch cannot provide isolation between editing-session workers.

This outline requires separate implementation and review.
The review contains no production edits.

## Executable evidence

Run `python3 Tests/OrgSourceReview/round1/torvalds/run.py` from the repository.

The probe compiles the production runtime and both production Org wrappers.
It runs thirteen ordinary fixtures with headings, nested lists, properties, timestamps, tables, blocks, links, markup, Unicode, and both newline conventions.
Each fixture receives a source append through `TSInputEdit`.
The probe compares the incremental tree with a fresh tree and checks all node ranges against source bytes.

| Build | Result |
|---|---|
| Intel, macOS 10.13 deployment target | 2,014 checks passed |
| Native arm64, macOS 11.0 deployment target | 2,014 checks passed |

The separate arm64 executable checks portable C integration. It does not change the Intel application target.

The package checks passed:

- Every vendored file matched its recorded byte count and SHA-256 hash.
- All six Org files matched the pinned upstream revision byte for byte.
- The built application carried the exact Org query and the required license notice.
- The built application registered `.org` and its plain-text UTI.
- The built Intel executable recorded macOS 10.13 as its deployment target.

The host ran macOS 26.5.2 with Xcode 26.6, build `17F113`.
The checked application binary SHA-256 was `e7444eb06146ddf7c20949a99c127fbadc31a11b3af2edb62b0a59b0075b8628`.

## Limits

The deployment-target check does not prove execution on macOS 10.13.
The ordinary fixtures do not prove that all Org documents parse correctly.
The native probe does not exercise TextKit, window routing, Undo, or application lifecycle.
Other review evidence covers those areas.
The pre-existing shared-text and GUI activation failures are outside this finding.

Evidence files: `probe.c`, `run.py`, `output.txt`, and `metadata.json` in this directory.
