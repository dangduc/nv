# Round 1: runtime and build cost

Reviewed commit `2dbfd46` against `bd74bf3`. This review uses a performance and measurement perspective inspired by Dan Luu.

## Finding: P2 — Resolve the URL prefix once per wiki-link scan

Location: `Sources/Editor/AttributedPlainText.m:329`. Related helper: `Sources/Application/NVAppIdentity.h:5`.

Each wiki link now reads bundle metadata and creates the same URL prefix again. The application flavor stays constant during a scan.

The exact old and new scan methods produced these median times in a standalone Cocoa process:

| Flavor | Links | Old | New | Added time |
| --- | ---: | ---: | ---: | ---: |
| Release | 10 | 0.026 ms | 0.049 ms | 0.024 ms |
| Release | 1,000 | 2.746 ms | 5.111 ms | 2.365 ms |
| Release | 10,000 | 27.483 ms | 51.511 ms | 24.029 ms |
| Development | 10 | 0.026 ms | 0.053 ms | 0.027 ms |
| Development | 1,000 | 2.704 ms | 5.010 ms | 2.306 ms |
| Development | 10,000 | 27.404 ms | 51.656 ms | 24.251 ms |

The helper alone took about 1.8 microseconds per call. The dense-note scan took about 1.87 times its previous duration in Release.

`NVSourceLinkRuns` scans the complete source snapshot. `NVSourceAnalysis` runs these scans on one serial queue shared by editing sessions. Thus, repeated metadata reads delay link updates and other queued analyses. The test does not demonstrate blocked keystrokes or main-thread latency.

Resolve the scheme and prefix once before the wiki-link loop. Keep the value local to the scan to preserve bundle metadata behavior.

## Other hypotheses

Both actual app bundles passed the existing identity checks. The development bundle occupied 11,375,249 bytes. The release bundle occupied 7,796,748 bytes. These are sums of file sizes, not compressed download sizes.

Each configuration contained 115 object files. Each build log recorded 115 C-family compile commands, 42 XIB compile commands, and one link command. Both logs recorded successful builds. CI now compiles both configurations. That additional work follows the requirement to check both app identities. No build-cost finding follows from these counts.

## Method and limits

`run.py` extracts the exact scan methods from the two frozen commits. It uses the production percent-escape method and current identity helper. It compiles an Intel executable with `-O2` and runs it through Rosetta. Temporary app bundles supply Release and Development flavor metadata.

The test alternates old and new scans. It discards the first scan for each size and reports the median of eight remaining scans. Each scan uses a fresh attributed string. The test checks link counts and schemes after each scan. A separate loop measures 500,000 helper calls per sample.

The host ran macOS 26.5.2 and Xcode 26.6. Other review tests ran concurrently, so these measurements describe local conditions. The repeated paired results limit the effect of that noise. No GUI session, user notes, preferences, or keychain data participated.

The largest input contains 10,000 wiki links and repeated body text. It provides a workload bound, not a typical-note claim. The input with ten links shows a small absolute cost. The input without links fell below timer resolution. The benchmark measures the wiki-link scan, not complete source analysis or visible update latency.

The build logs lack elapsed times. Command counts cannot establish total CI duration or remaining timeout margin. This review did not repeat the builds.

## Reproduction

Run from the repository root:

```sh
python3 Tests/DevelopmentBuildReview/round1/luu/run.py
```

The executable check passed. Raw samples are in `development-raw.txt` and `release-raw.txt`. Summary measurements are in `results.json`. Build command counts are in `build-work.json`.
