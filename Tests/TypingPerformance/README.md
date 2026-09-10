# Production typing benchmark

This benchmark sends repeated key events to a copied Development app.
The copy uses 20 disposable notes and a separate preferences domain.
It does not disable production work or change scheduling.
Three wrappers count refresh, header, and highlight calls.

The benchmark uses Plain Text, Menlo 12, an empty query, and an 800-by-600-point content area.
It runs three trials for each case:

- A short note with word count hidden: 200 keys.
- A 100 KB note with word count visible: 80 keys.
- A 100 KB single line with word count hidden: 80 keys.

Each key has a 25 ms run-loop interval after dispatch.
The event carries the repeat flag after the first key.
Each edit must reach the model immediately and preserve the insertion offset.
The benchmark checks the final result count and library checkpoint.

Main-thread CPU includes event dispatch, run-loop work, and deferred drawing.
Key timing measures synchronous event dispatch only.
Neither measurement establishes presented frame timing or reproduces physical held-key input on another macOS release.

## Run

Build the Development app with the command in [AGENTS.md](../../AGENTS.md).
Then run:

```sh
python3 Tests/TypingPerformance/run.py
```

To compare another app, supply its path and a separate output directory:

```sh
python3 Tests/TypingPerformance/run.py --app /path/to/nvALT.app --output build/TypingPerformance/baseline
```

The runner writes `timings.json`, `results.json`, and `native.log` under the output directory.
The result record includes the executable hash.
The runner shares the desktop-test lock across Git worktrees.

Compare matching reports with:

```sh
python3 Tests/TypingPerformance/compare.py build/TypingPerformance/baseline/timings.json build/TypingPerformance/candidate/timings.json
```

The comparison reports the median of each case's three trials.
Run both apps under comparable host load and desktop conditions.
