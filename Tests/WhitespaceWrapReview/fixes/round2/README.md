# Round-two correction

The glyph delegate now returns before source queries when no eligible elastic property exists.
Changed batches of at most 64 properties use a fixed stack buffer.
Larger changed batches retain the guarded heap path.
The source characters, glyphs, properties, and wrapping policy are unchanged.

The [buffer evidence](buffers/findings.md) compares the original and optimized methods under ASan and UBSan.
It checks guarded inputs, allocation failure, stack boundaries, and native layout equivalence.

The [performance attribution](perf/findings.md) identifies the avoidable allocation work in the actual app.
The [before-and-after comparison](perf/correction.md) reports the improvement and remaining resize cost.
The optimization reduces the measured increment; it does not make every large note resize quickly.

The original round-two finding and baseline results remain unchanged.
