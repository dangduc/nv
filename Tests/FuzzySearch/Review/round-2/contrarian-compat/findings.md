Round two found no new actionable compatibility defect in the checked paths.
The native and sanitizer runs each passed 279 assertions. These assertions require the intended behavior and contain no failure witnesses.

The reviewed browser methods match `6d66102`. That commit includes the latest-selection correction after the round-one mode repairs.
Each run copied production sources into a separate build directory before compilation. The JSON records contain the compiled source and method hashes.
This capture allowed the separate service repair to continue without a requirement that its live files remain unchanged.

**Commands and results**

| Command | Result | Record |
| --- | --- | --- |
| `python3 Tests/FuzzySearch/Review/round-2/contrarian-compat/run.py` | Pass, 279 assertions | `native-results.json` |
| `python3 Tests/FuzzySearch/Review/round-2/contrarian-compat/run.py --sanitize` | Pass, 279 assertions, no address or undefined-behavior diagnostic | `sanitize-results.json` |

The runs used native arm64 on macOS 26.5.2 (25F84), with Xcode 26.6 (17F113). No Intel process ran.

**Checked behavior**

- Absent preferences keep a new Fuzzy session. A present empty legacy query selects Exact.
- An explicit empty Fuzzy query keeps Fuzzy in preferences and window state. It displays one ordinary row per note.
- Invalid modes fall back to Exact. Missing, malformed, obsolete, and foreign occurrence keys cannot select a different note.
- Preferences, windows, and bookmarks preserve a valid Fuzzy occurrence. An unavailable title occurrence falls back to the available Fuzzy occurrence.
- The production preference writer and reader preserve the selected occurrence through an asynchronous search.
- A newer mode-less window restoration replaces pending Fuzzy preferences and selects the window's note in Exact mode.
- A newer bookmark replaces pending window restoration. A newer window restoration also replaces pending bookmark selection.
- An explicit newer preference restoration replaces an older pending window selection.
- Completion consumes the saved selection intent. Repeated current completions do not revive an older selection.
- A legacy external search replaces pending saved selection and retains Exact semantics.
- The repaired Tab path preserves Fuzzy mode, all four fixture rows, and the gapped body match.
- The fixture retains title-first overlap: four displayed rows represent three notes. Its Fuzzy tail equals the complete native ordered result.
- Archive identities survive lazy note resolution and deletion. Distinct bookmark occurrences remain distinct without extra note models.

**Limits**

The fixture runs production archive, preference, command, and restoration methods with the real browser session and native search implementation.
Deterministic controls and in-memory notes replace AppKit event delivery and the disk library. An isolated defaults object prevents personal preference access.
The startup cases begin with the Fuzzy session that library attachment supplies. They do not run complete application startup or nib loading.
The preference-after-window case exercises an explicit method order. It does not claim that normal startup uses that order.
The dormant saved-search archive model is covered. Its obsolete controller preference API remains outside the application target and this runtime fixture.
The source capture identifies the service implementation used by each run. These results do not assess the separate service callback-ownership repair.
The original Intel desktop suites remain outside this focused review because Rosetta execution stalls on this host.

This review added only files in its round-two directory. It changed no production file, original test, or earlier review file, and created no commit.
