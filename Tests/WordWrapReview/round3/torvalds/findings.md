# Round 3 findings

No new actionable issue was verified.
The production null-return guards preserve native fallback, source text, and explicit Core Text ownership in these cases.

| Result | arm64 | x86_64 |
| --- | ---: | ---: |
| Cases | 36 | 36 |
| Behavior checks | 1,009 | 1,009 |
| Injected typesetter creation failures | 58 | 58 |
| Injected first-line creation failures | 24 | 24 |
| Injected extended-line creation failures | 24 | 24 |
| Completed paragraph callbacks | 144 | 144 |
| Tracked creates and releases | 464 / 464 | 464 / 464 |
| Outstanding tracked references | 0 | 0 |
| ASan or UBSan diagnostics | 0 | 0 |

The guard at `Sources/Editor/NVSourceTypesetter.m:60` handles failed paragraph measurement creation.
The guards at lines 104 and 108 handle failed line creation.
Each failed layout matched the complete native character-layout snapshot.
The source remained unchanged after each failure and successful retry.
Each retry also matched a fresh production text system.

The ownership negative control omits `CFRelease(line)` from a generated build copy.
It fails at check 25 with the expected ownership assertion.
This result shows that the reference counter detects a missing release without relying on framework memory totals.

Both runs used macOS 26.5.2 (25F84) and Xcode 26.6 (17F113).
The x86_64 run used Rosetta on the same host.
The production digest remained `c8045359e5d821a3c8ae55abb454de4a979cfa15273b25380152847bfe7b71f9`.

The injected null results do not simulate actual memory exhaustion.
The suite does not cover native exceptions, tokenizer creation failure, or arbitrary attributed text.
The parent review owns the full application build and desktop suites.
