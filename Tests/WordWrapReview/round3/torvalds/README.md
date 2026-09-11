# Round 3: Core Text creation failures

This review covers commit `63911bf2c66d438f178b43a8b9e996787e29acc9`.
It uses a correctness and minimality perspective inspired by Linus Torvalds.
It does not represent his review or endorsement.

Run the two architectures and the ownership negative control:

```sh
python3 Tests/WordWrapReview/round3/torvalds/run.py --arch arm64
python3 Tests/WordWrapReview/round3/torvalds/run.py --arch x86_64
python3 Tests/WordWrapReview/round3/torvalds/run.py --negative-control
```

The runner compiles the actual production typesetter with a forced include of `fault_hooks.h`.
Only that production translation unit uses the call macros.
The harness and native reference layout use the real framework calls.
The space delegate comes directly from the current `LinkingEditor.m` implementation.

The hooks inject null results at three creation points:

- The paragraph typesetter creation.
- The first measured line creation.
- The extended line creation, after the first line succeeds.

The hooks also count created references and production releases.
The 32-entry table stores raw pointers without retaining them.
Precondition checks reject a null argument before it reaches a later native measurement call.

The suite checks two boundaries:

| Boundary | Independent behavior check |
| --- | --- |
| A creation failure preserves native fallback. | The complete line ranges, rectangles, and glyph positions equal native character layout with the same source attributes. |
| Failure cleanup permits later successful layout. | Every tracked reference receives a release, both caches clear, and a successful retry equals a fresh production layout. |

The 36 cases use three source fixtures, two widths, two alignments, and three failure modes.
The fixtures include Latin words, Hebrew, emoji, combining marks, Chinese, and multiple paragraphs.
All text systems remain windowless.

The negative control removes one line release from a generated copy under the build directory.
The ownership assertion must reject that bounded copy.
The runner treats the expected assertion failure as a successful negative control.
The control does not remove null guards or submit invalid pointers to native APIs.

The suite enables ASan and UBSan for the production object and harness.
The native frameworks remain uninstrumented, and leak detection is disabled.
The checks cover explicit create/release balance, not native framework retention.
They do not simulate actual memory exhaustion or establish behavior on older macOS versions.

Full results are under `build/WordWrapReview/round3/torvalds/`.
Each summary records the production commit and SHA-256 digest.
Production files and earlier review rounds remain unchanged.
