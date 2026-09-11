# Round 2: cleanup callback order

This review covers commit `4c8f6b449504a50caa460d78efebd42b94beaba6`.
It uses a correctness and minimality perspective inspired by Linus Torvalds.
It does not represent his review or endorsement.

The probe links the production typesetter and extracts the production space delegate.
It does not change either implementation for the normal runs.
The probe creates windowless Cocoa text systems with one or three containers.

Run both architectures and the callback-order negative control:

```sh
python3 Tests/WordWrapReview/round2/torvalds/run.py --arch arm64
python3 Tests/WordWrapReview/round2/torvalds/run.py --arch x86_64
python3 Tests/WordWrapReview/round2/torvalds/run.py --negative-control
```

The runner enables AddressSanitizer and UBSan for the production implementation and test code.
The native AppKit and Core Text frameworks remain uninstrumented.
Leak detection is disabled because these checks cover invalid accesses and undefined behavior.

The test subclass observes the production begin, end, and cleanup methods.
A temporary runtime wrapper observes the native `NSATSTypesetter.endParagraph` implementation.
The wrapper calls the original implementation and records its return before production cleanup continues.
The probe restores the original implementation before exit.

The negative control changes only the generated build copy of `endParagraph`.
It moves cleanup before the native callback.
The callback-order assertion must reject that copy.
The runner treats that expected assertion failure as a successful negative control.

The behavior checks cover three hypotheses:

| Hypothesis | Evidence |
| --- | --- |
| Cleanup follows the native paragraph callback. | Each observed native return precedes cleanup. Completed callbacks leave both analysis pointers empty. |
| Cleanup preserves later source layout. | Font edits, width changes, note replacement, and finite containers produce the same geometry as fresh production text systems. |
| Repeated cleanup and destruction remain safe. | Forty cycles call cleanup twice, replace the note with empty source, and destroy the text system under both sanitizers. |

The source fixtures contain 4,096-character prose, empty source, blank paragraphs, Hebrew, emoji, combining marks, and several paragraph separators.
The fixtures use Menlo 12 and 18, plus font changes to Helvetica 16.
Finite 44-point containers exercise paragraph continuation across containers and container exhaustion.

The runner also runs two isolated attribute-retention controls without the production typesetter.
Those controls explain why an arbitrary attributed marker cannot establish ownership by nvALT.
The report gives the observed result without a pass threshold.

Full outputs are under `build/WordWrapReview/round2/torvalds/`.
The summaries record the production commit and SHA-256 digest.
This review does not change the Round 1 records or the production files.
