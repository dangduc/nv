# Rejected measurement shortcut

The round-one performance finding prompted a temporary one-line measurement experiment.
The experiment used the next character's caret offset as the preceding word width for ordinary-space boundaries and monotonic, left-to-right runs.
Other runs retained the original two-line measurement.

A differential probe compared the experiment with the published typesetter across 1,512 font, size, width, kerning, and multilingual fixtures.
Eleven snapshots differed. All differing cases had explicit nonzero kerning.
The existing standard matrix still passed, so it did not expose these differences.

The separate six-trial benchmark also showed worse performance.
For eight beginning edits in a 131,050-character paragraph, the experimental layout cost about 98.2 ms per edit.
Its character-layout control cost 21.3 ms per edit.
The published implementation measured 28.1 ms against a 19.4 ms control in the earlier review run.
These are separate runs on the same host, not a noise-free comparison.
The difference was sufficient to reject this implementation.

The experiment did not change production code.
It explains why the round-one performance finding is documented instead of addressed through caret-offset substitution.
The existing two-line measurement preserves independent typographic widths.
The retained paragraph cache receives a separate lifetime correction.

Local sources, measurements, and logs remain under `build/WordWrappingOptimization/`.
This record does not claim a general lower bound for alternative typesetter designs.
