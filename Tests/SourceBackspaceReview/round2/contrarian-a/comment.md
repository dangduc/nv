Round 2 — Contrarian A: evidence validity and test reliability.

Two findings:

- **[P2] Reject inherited first-case mode in normal runs.** `Tests/SourceBackspace/run.py` inherits `NV_BACKSPACE_REPRO_ONLY` and accepts the early completion marker as full success. Controlled output with 12 checks produced `passed: true` in normal mode. Remove the inherited switch and require a distinct full-suite completion marker.
- **[P2] Require the expected mutation assertion.** `Tests/FuzzySearch/HighlightBounds/run.py` treats any nonzero mutant exit as a successful rejection. Its actual function accepted simulated loader failure 127 and signal -11 without the intended assertion. Require the expected assertion and exit code for each mutation.

The fixed app already passed 310 native checks. The saved mutation logs also contain the intended assertion failures. These findings concern gaps in future result classification.

Evidence: `Tests/SourceBackspaceReview/round2/contrarian-a/{run.py,output.txt,manifest.json,report.md}`. The 21 checks exercised runner decisions with simulated child results. They did not launch nvALT or run native editor checks. The manifest preserves the historical tested hashes.
