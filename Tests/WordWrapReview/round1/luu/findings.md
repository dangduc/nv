# Round 1: performance review

This review uses a Dan Luu-inspired measurement perspective. It does not represent Dan Luu or his endorsement.

## P3: bound the added work for large paragraph invalidations

[The production typesetter](../../../../Sources/Editor/NVSourceTypesetter.m#L45) adds synchronous Core Text measurement during native layout.
Its line-break table and measurement snapshot reset at each paragraph layout.
[Each narrowed line also creates two CTLine objects](../../../../Sources/Editor/NVSourceTypesetter.m#L90).
This work adds measurable latency while editing near the beginning of a large paragraph or resizing its visible viewport.

The practical trigger is one long paragraph of prose, Menlo 18, a 544-point text container, and edits near offset 32.
A bounded 600-point viewport request causes native layout to cover the full paragraph in both modes.
The following medians divide each eight-operation sample by eight.

| Paragraph characters | Base edit ms | Candidate edit ms | Base resize ms | Candidate resize ms |
| --- | ---: | ---: | ---: | ---: |
| 4,050 | 0.649 | 0.939 | 0.602 | 0.888 |
| 32,750 | 5.202 | 7.393 | 4.894 | 6.994 |
| 131,050 | 19.412 | 28.149 | 18.931 | 26.868 |
| 524,250 | 77.322 | 113.392 | 76.347 | 110.288 |

At 131,050 characters, the candidate edit cost was 1.45 times the control cost.
Process CPU medians were 19.413 and 28.112 ms per edit, respectively, close to wall time.
Both modes already incur substantial native layout cost. This finding concerns the additional cost introduced by PR 28.
A paragraph-length or work-budget fallback to existing character wrapping can bound the added work, subject to the desired large-note behavior.
Reducing duplicate line measurement is another candidate. It needs geometry and performance evidence before adoption.

## Attribution and controls

The separate instrumented run linked the same production file, with wrappers around its Core Text and tokenizer calls.
Eight beginning edits at 131,050 characters created eight typesetters from snapshots covering 1,048,436 UTF-16 units in total.
Those edits advanced 209,688 tokenizer tokens and created 22,068 CTLine objects.
The initial layout contained 2,675 native lines and 2,759 candidate lines, only 3.1% more.
The extra lines alone do not explain the measured edit-cost increase.

End edits benefit from native partial paragraph layout.
At 131,050 characters, end edits took 0.330 ms in the control and 0.363 ms in the candidate.
Their eight measurement snapshots contained only 592 UTF-16 units in total.
The cache therefore does not always rebuild the entire source paragraph after every edit.

The 100-character short note took 0.031 versus 0.059 ms per beginning edit.
Its absolute increase was 0.028 ms per edit. This does not support a short-note typing-stutter finding.
Documents containing short newline-separated paragraphs retained bounded visible layout, despite their larger total source size.

## Evidence and limits

The reviewed head is `4b049709b2cecc6eac80514586ccacc119d12802`, compared with base `b6a5696`.
The native control retains the actual space glyph delegate and character paragraph wrapping, and omits only `NVSourceTypesetter`.
[The runner](run.py) links the actual production implementation. [The README](README.md) describes the operations and reproduction commands.
[Primary timings](results.json) use one warmup and six samples per case, alternating mode order.
The [separate call-count run](instrument-results.json) is excluded from timing conclusions.
The primary run passed 1,569 checks. The call-count run passed 161 checks, including evidence writes.

The probe ran on macOS 26.5.2 (25F84), x86_64 under Rosetta, with `-O1` and the macOS 10.13 deployment target.
Source construction and result collection were outside timed intervals. Source mutation and requested layout were inside them.
All operations ran on the main thread in standalone native text systems.
These results do not establish complete nvALT key-event latency, display-frame timing, or macOS 13 behavior.
The root reported no competing app timing benchmark during measurement. Ordinary host scheduling still adds noise.

An initial mixed-Unicode run was stopped because native bidi layout dominated its runtime.
No measurements from that interrupted run support this finding. The completed run uses plain prose and short-paragraph controls.

A proposed one-line measurement optimization must treat caret offsets and standalone line widths as different quantities until geometry confirms equivalence.
Boundary shaping, kerning, trailing spaces, and mixed-direction runs need explicit controls before replacing the current two-line measurements.
