Round 1 — Contrarian A: challenge added complexity and the causal claim.

No actionable finding. The extracted production methods pass 16 native AppKit checks. Five reduced variants fail the intended assertions:

- No suppression: the draw delegate returns the old background before cleanup.
- No cancellation: the old callback removes fresh search results.
- No edit guard: a clear mutates temporary attributes inside an open character edit.
- No generation advance: the old async generation remains valid.
- No pre-detach cleanup: the old callback acts on replacement storage.

The last control establishes callback ownership, without proof of a visible error by itself. Four additional checks restore the original methods. Those checks pass with an uncached layout, so deletion alone does not establish the crash. The copied-app regression provides the cached-window exception evidence.

Evidence: `Tests/SourceBackspaceReview/round1/contrarian-a/{run.py,probe.m.in,output.txt,manifest.json,report.md}`. The manifest records unchanged production hashes. These checks use macOS 26.5.2 without a window. They do not establish macOS 13.7.8 behavior or IME pixel behavior.
