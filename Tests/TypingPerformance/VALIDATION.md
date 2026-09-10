# Typing change validation

The initial production comparison uses upstream master at `8dde5e89578f99dd10751e653eb8d45c298bf72b`.
Both apps ran on macOS 26.5.2 (25F84), Xcode 26.6 (17F113), under Rosetta.
The Development build targets Intel and macOS 10.13.
These results do not establish behavior on the reported macOS 13.7.8 host.

Each app completed 1,080 checked edits across three trials per case.
Both retained immediate model commits, correct insertion offsets, 20 result notes, and a successful final checkpoint.
The benchmark contains no production skip toggles.

| Case | Keys per trial | Master main CPU | Initial change main CPU | CPU reduction | Master mean key dispatch | Initial mean key dispatch |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Short note, count hidden | 200 | 2000.1 ms | 964.6 ms | 51.8% | 2.698 ms | 3.237 ms |
| 100 KB note, count visible | 80 | 2715.0 ms | 381.0 ms | 86.0% | 25.978 ms | 6.945 ms |
| 100 KB single line, count hidden | 80 | 3741.0 ms | 616.9 ms | 83.5% | 40.217 ms | 6.828 ms |

Values are medians of three trials. Key dispatch includes synchronous event handling only.
Main-thread CPU includes deferred work and drawing during the run-loop intervals.
Reduced CPU does not imply the same reduction in visible stutter.
Short-note dispatch time increased slightly despite lower total CPU.
Physical held-key input and presented frame timing on macOS 13 remain manual checks.
The earlier space-character behavior remains outside this change.

[Master samples](measurements/master.json) and [initial change samples](measurements/initial-change.json) contain all trial measurements.
The executable SHA-256 values identify the tested binaries:

- Master: `6a9bc7b304e40072de11e2a976c7d18c89dc41188d3be82bb9deaad3a31c43a7`.
- Initial change: `1d4ca5d7db470f261a7abf458952b526f7c3c8e548fdf33a86fa06e80f3485b0`.
