# Round 1: test evidence review

The review found one coverage gap. The current app passed the automatic appearance check.

The reviewed production source was `10de8a4`, against baseline `116daff`. HEAD was `8d744e2`, which adds review screenshots and documentation. The host ran macOS 13.7.8 and Xcode 15.2. The probe used the existing x86_64 Development app under Rosetta.

## P2: Exercise the automatic appearance callback in the regression test

Location: `Tests/Regression/native-ui/checks.inc:134-138`.

The test changes the window appearance, then calls `browserAppearanceChanged` directly. This direct call bypasses the callback that the user depends on. The automatic callback lives at `AppController_BrowserUI.m:20-22`.

A test-only mutation removes the callback forwarding and retains the superclass implementation. The original suite still passes all 41 checks. Its log records four calls to the mutated callback. Thus, the passing appearance assertions do not establish automatic appearance updates.

The stronger probe removes only the direct call at test line 135. The current app passes all 41 checks. The mutated app fails the dark background assertion after 38 passing checks. This result establishes a coverage gap, not a current appearance defect.

The acceptance test needs an appearance transition without a direct controller update. The callback mutation provides a negative control for this requirement.

## Executable evidence

Command, run with sandbox escalation for Cocoa and Rosetta:

```sh
python3 Tests/NativeUIReview/round1/test_contrarian/run-canaries.py
```

The runner holds `build/pr-review/gui.lock`. Each run uses a copied app, a unique bundle identifier, and temporary notes, support files, and preferences. The runner removes its preferences after each run. It neither builds nor changes the shared app.

The runner uses the current regression fixture. The automatic variant removes exactly one direct update call. `appearance_mutation.m:6-10` defines the omitted forwarding. `appearance_mutation.m:22-26` installs the mutation only in the copied test app.

Observed output:

```text
original-baseline: exit=0 assertions=41 mutations=0
original-mutation: exit=0 assertions=41 mutations=4
automatic-baseline: exit=0 assertions=41 mutations=0
automatic-mutation: exit=1 assertions=38 mutations=3
FAIL: system editor background follows the window appearance
CANARY CONFIRMED: original checks miss callback removal; automatic checks detect it.
```

Full output is in `original-baseline.txt`, `original-mutation.txt`, `automatic-baseline.txt`, and `automatic-mutation.txt` beside this report.

## Checks without findings and limits

- The unmodified app passed the original 41 native UI assertions.
- Automatic Aqua and Dark Aqua transitions passed without the direct update call.
- Explicit editor colors survived an appearance change in the automatic baseline.
- The probe changes the window appearance through AppKit. It does not change the global macOS appearance preference.
- The body contrast assertion reads temporary drawing attributes. This review does not establish pixel contrast or selection visibility.
- The optional full-screen path was disabled. No live sync service, external editor, or personal notes were used.
