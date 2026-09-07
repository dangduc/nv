# Round 2: test evidence review

This review found no actionable gap for the two selected faults. The unchanged acceptance fixture passed all 68 assertions. Each activated fault failed its intended behavior assertion.

The source HEAD was `12936fed78e1d98ac646bb88b51e009609ad505e`. The host ran macOS 13.7.8 (22H730) and Xcode 15.2 (15C500b). The probes ran against the existing x86_64 Development app under Rosetta.

The tested executable SHA-256 was `f9d0a299a852c80fae0574722776d5e732031fec6f4c328861e57d74d9d00228`. `provenance.json` records the executable and acceptance source hashes. The runner compared these hashes before and after all three runs. The hashes stayed unchanged.

## Faults and observed results

| Case | Expected result | Observed result |
| --- | --- | --- |
| Unmodified app | All acceptance assertions pass | 68 passed, no mutation calls, no failures |
| Omit appearance forwarding | Background assertion fails during the appearance transition | 65 passed, 5 mutation calls, expected failure |
| Restore library-only metadata Undo | Body Undo-enabled assertion fails after Return commits the title | 19 passed, 1 mutation call, expected failure |

The appearance mutation replaces `NVBrowserContentView.viewDidChangeEffectiveAppearance`. It retains the superclass call and omits controller forwarding. The production forwarding is at `AppController_BrowserUI.m:22`.

The unchanged fixture changes the window appearance at `Tests/Regression/native-ui/checks.inc:147`. It contains no direct call to `browserAppearanceChanged`. The faulty app passes the Aqua background and contrast assertions. Its automatic Dark Aqua callback runs, then the background assertion fails at `Tests/Regression/native-ui/checks.inc:149`.

The metadata mutation restores the implementation from the parent of `12936fed`. It registers metadata history only in the library undo manager. The current replacement delegates to the note editing session at `NVApplicationController.m:250`.

The faulty app commits the edited title. Its mutation log reports `title=1 libraryCanUndo=1 noteCanUndo=0`. The next assertion fails at `Tests/Regression/native-ui/checks.inc:58`. That assertion requires body focus and an enabled Undo action after Return. The unmodified app passes this assertion and subsequent responder Undo and Redo assertions for titles and tags.

`mutations.m:8` defines the appearance fault. `mutations.m:15` defines the metadata fault. `mutations.m:33` installs a selected fault only inside the copied app and its unique preference domain.

## Executable evidence

Command, run with sandbox escalation for Cocoa and Rosetta:

```sh
python3 Tests/NativeUIReview/round2/test_contrarian/run-canaries.py
```

The runner exited with status 0. Its final message was:

```text
CANARIES PASSED: unchanged acceptance passes; both activated faults fail their intended assertions.
```

The two fault logs contain these exact failures:

```text
FAIL: system editor background follows the window appearance
FAIL: Return focuses the body with metadata Undo enabled
```

`results.json` records the counts and assertion results. `baseline.txt`, `appearance-fault.txt`, and `metadata-fault.txt` contain the full app output. All three probe compilations succeeded without compiler output.

The runner uses `open -W -n --env` for each copied app. Launch Services returned status 0 for all three runs. Thus, the runner uses explicit success and failure markers to judge the fixture result. It does not treat the launcher status alone as an acceptance result.

The runner holds `build/pr-review/gui.lock` and sets a 90-second timeout for each run. Each app copy uses temporary notes, support files, and a unique preference domain. The fixture disables external editor initialization and bypasses normal sync startup. Each run removes its preference domain and temporary files.

## Limits

- These two canaries support closure of the selected appearance and metadata Undo coverage concerns.
- The metadata fault stops at title Undo availability. It does not independently reach the faulty tag Undo path.
- The appearance check sets the window appearance through AppKit. It does not change the global macOS appearance preference.
- The checks inspect view state and drawing attributes. They do not establish pixel contrast or physical keyboard event delivery.
- This review did not run the optional full-screen path or repeat the full regression suite.
- No production code, acceptance source, or shared app changed. No personal notes or live services were used.
