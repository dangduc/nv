# fzf-native source subset

This directory contains the matcher and Unicode support from [`dangduc/fzf-native`](https://github.com/dangduc/fzf-native).
The pinned `main` revision is `4b9236e8cd1e9f9f3aaf5f2ebf83f1fc5995d38d`, downloaded September 9, 2026.
`upstream.json` records each file digest and the local change to utf8proc.
The utf8proc size-only decomposition and recursive sequence expansion avoid pointer arithmetic on NULL output buffers.
These guards preserve normalization output and removes undefined behavior exposed by the NFC preparation tests.
All other vendored source and license files remain unchanged.

The application compiles `fzf.c` and `utf8proc-2.10.0/utf8proc.c` with `UTF8PROC_STATIC`.
The remaining headers and include files support these sources.
Emacs bindings, binaries, upstream benchmarks, shell producers, and unused adapters are excluded.

`Sources/Search/NVFZF.c` owns the nvALT interface. Its native ranking and term helpers are separate source extractions.
[The bridge provenance](../../Sources/Search/ORIGIN.md) records those boundaries and the ownership contract.
`Tests/FuzzySearch/Core/run.py` checks file digests and compares native result order with an independent upstream reference.

`LICENSE` contains GPL-3.0 for the module-derived ranking code.
`LICENSE-MIT` contains the matcher notices, including SIMD adaptations.
`utf8proc-2.10.0/LICENSE.md` contains the utf8proc and Unicode notices.
