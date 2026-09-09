# Search service measurements

Measured September 9, 2026, on arm64 macOS 26.5.2 (25F84), with Xcode 26.6 (17F113).
These measurements cover the production search service in a Foundation executable.
They exclude AppController, table publication, painting, and Intel execution.

Run from the repository root:

```sh
python3 Tests/FuzzySearch/run-service-tests.py --benchmark
python3 Tests/FuzzySearch/run-service-tests.py --benchmark --long-line-only
```

The generated corpus contains 10,000 notes and 52,826,668 candidate bytes.
Candidates contain titles, tags, and complete 5,243-character source strings.
Deterministic UUIDs distribute bytes throughout each identifier.
Twelve warm queries use different terms. Instrumentation measures preparation, title matching, and result construction separately.
The reported p95 uses nearest rank over these twelve samples; it is not a production latency guarantee.

| Measurement | Result |
| --- | ---: |
| Initial corpus synchronization | 4.085 ms |
| Cold `mtg` search | 613.931 ms |
| Warm search median | 1,020.911 ms |
| Warm search p95 | 1,345.700 ms |
| Process peak resident memory | 318,439,424 bytes |
| 1 MiB Unicode preparation cancellation | 9.695 ms |
| 1 MiB Unicode normalization cancellation | 5.640 ms |
| 1 MiB warm matcher cancellation | 3.318 ms |
| 8 MiB Unicode preparation cancellation | 14.474 ms |
| 8 MiB Unicode normalization cancellation | 49.084 ms |
| 8 MiB warm matcher cancellation | 36.716 ms |

Cancellation timing starts when the main thread cancels the request.
A test-only serial-queue marker records when the worker lane becomes available.
The fixtures use repeated decomposed `e` plus acute accents on one source line.
Normalization tests cancel after 5 ms or 40 ms, after UTF-8 conversion can finish.
Other cancellation tests cancel after 2 ms.

The initial implementation used Foundation NFC conversion.
Its 1 MiB cold cancellation took about 4.1 seconds. The combined 8 MiB run exceeded its 90-second timeout.
The service now uses the pinned utf8proc implementation for canonical composition.
The latest fixtures meet the proposed cancellation target. Individual conversion and matcher calls remain uninterruptible.
The proposed 150 ms search target remains unmet.

An earlier fixture used sequential integer UUIDs with a shared zero prefix.
Foundation dictionary insertion took 1.616 seconds for those 10,000 keys, versus 1.585 ms for random CFUUID keys.
That fixture distorted result-construction timings. It is excluded from the reported query measurements.
Fixture construction in the CSV includes generated source creation; it does not measure application snapshot capture.

Raw records: [complete corpus](service-arm64.csv) and [8 MiB source](service-8m-arm64.csv).
