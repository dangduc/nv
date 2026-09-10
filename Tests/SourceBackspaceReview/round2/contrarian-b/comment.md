Round 2/3 — Contrarian B: native appearance ownership.

No actionable finding. I wrote a new probe with four real, windowless NSTextViews. Paired views share storage and retain separate layout managers and opposite appearance settings.

All 48 checks pass. Cleanup preserves stored source colors, native selection settings, caret/body colors, and peer highlights. Native setMarkedText/unmarkText exercises actual composition state. Empty-result and missing-color transitions retire pending cleanup. Four deliberate defects fail 16 intended assertions.

The final run tested `5db853c`; its four production files match `c2209e2` and remained unchanged. Evidence: `Tests/SourceBackspaceReview/round2/contrarian-b/{run.py,report.md,manifest.json}` and saved candidate/control outputs.

Limits: no rendered pixels, actual input method, or candidate window. This setup retains marked-background configuration without exposing its rendered attributes, so it does not validate IME background pixels. Color/capture helpers are adapters. Tested on macOS 26.5.2 through Rosetta; macOS 13.7.8 remains untested.
