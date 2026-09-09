# Shared native bridge

The prototype compiles the same C bridge as nvALT through the thin `NVFZF.c` and `NVFZF.h` includes.
Its native fzf query syntax uses `nvfzf_search` and `nvfzf_positions`.
The production interface accepts typed literal terms through separate entry points.

[Sources/Search/ORIGIN.md](../../../Sources/Search/ORIGIN.md) records the dependency revision, extractions, licenses, ownership, and evidence limits.
The compatibility runner in `Tests/run.py` invokes the production suite under `Tests/FuzzySearch/Core/`.
There is no second scorer or sorter implementation in this prototype directory.
