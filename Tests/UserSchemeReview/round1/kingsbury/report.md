# Round 1 — Kyle Kingsbury correctness perspective

This review uses a Kingsbury-inspired perspective. It does not claim his authorship or endorsement.

No actionable PR defect was found in the tested schedules.

Reviewed production `3297f6e` against `78d9442`. The frozen app ran on macOS 26.5.2 (25F84), Xcode 26.6 (17F113), Intel under Rosetta. Its executable SHA-256 was `8060f1cb71a119e94bce789df38494c100719eaf744a4fb72df9684f7f7858f1`.

## Executable evidence

```sh
python3 Tests/ViewControlsReview/run-probe.py \
  --app build/UserSchemeReview/initial/nvALT.app \
  --probe Tests/UserSchemeReview/round1/kingsbury/probe.inc \
  --prefix Tests/UserSchemeReview/round1/kingsbury/prefix.h
```

Result: exit 0, **80 checks passed**, including fixture checks. See [output.txt](output.txt), [probe.inc](probe.inc), and [prefix.h](prefix.h).

The probe holds actual worker completions immediately before browser publication. It intercepts both literal-range scans and validation of native Fuzzy positions. It counts editor publication calls and checks colors against an independent channel-by-channel alpha-composite calculation.

- Two browsers share one note and source storage. They start with opposite appearances, then swap appearances through AppKit callbacks. Exact and Fuzzy searches publish the new palette in each editor.
- Old completions then arrive in reverse order, twice each. Neither browser publishes those stale ranges, and both retain their current highlight colors.
- Dark background and highlight preferences change consecutively while a Fuzzy completion is held. The latest completion uses both new values. The old completion cannot publish afterward.
- A peer closes with a held completion. A new browser selects the same note using the latest dark palette. Late callbacks publish to neither the detached editor nor its replacement.
- The note count and complete attributed source remain unchanged throughout these schedules.

## Interpretation and limits

The existing generation fence in `AppController_Search.m:158–185` rejects obsolete results after the new palette refresh. `LinkingEditor.m:473–484` selects the current owning browser's palette when valid ranges publish. The tested behavior preserves that separation across shared source storage and window replacement.

The first Fuzzy fixture searched a term also present in the title. Native Fuzzy matching correctly returned title positions without source ranges. The corrected fixture uses a body-only term. This was a fixture error, not a PR defect.

Holding completed callbacks and delivering duplicates is synthetic. It exceeds the service's normal single-delivery contract and tests the browser's defensive publication fence. The probe retains callback captures and the detached editor, so it does not establish deallocation or leak behavior. It checks selected schedules rather than all interleavings. It does not test preference durability or operating-system versions older than this host.
