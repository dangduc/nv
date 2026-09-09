# Round 2: Ousterhout engineering perspective

This review uses an engineering perspective inspired by John Ousterhout. It does not claim his authorship or endorsement.

No actionable PR defects found in this round.

I read all five Round 1 reports and the appearance-compatibility fix and its evidence.
This review covers production commit `3297f6e` with the subsequent `browserAppearanceChanged` compatibility fix.
The reviewed fallback saves the caller's appearance, applies the browser appearance, and restores the caller's appearance in `@finally`.

## Independent evidence

The native probe passed **109 checks**, including fixture checks.
It uses two actual `AppController` instances and their native windows, editors, and shared note storage.
It does not substitute small controller or window stand-ins.

```sh
python3 Tests/UserSchemeReview/round2/ousterhout/run.py \
  > Tests/UserSchemeReview/round2/ousterhout/output.txt 2>&1
```

The command exited with status 0.
See [run.py](run.py), [prefix.h](prefix.h), [probe.inc](probe.inc), and [output.txt](output.txt).

The update instrumentation invokes the light peer's appearance update from inside the dark browser's update.
It then calls the original `updateColorScheme` implementation.
Four User/System scheme combinations run through both the rebuilt binary's modern path and the forced fallback path.
Each combination runs once successfully and once with an exception injected inside the nested update.

The assertions establish these results:

- Each native browser update observes its own current appearance.
- A successful nested update restores the outer browser's appearance before the outer browser performs its real update.
- Both successful browser updates retain the expected User or System foreground, background, and editor background.
- An injected nested exception reaches the caller. Both appearance scopes unwind and restore the original caller appearance.
- Every case invokes exactly one outer update and one nested update.
- All successful and failed cases preserve the complete shared source attributes.

The wrapper extracts the corrected production method into a temporary probe file.
It renames the method and replaces only the modern-path choice with `if (NO) { }`.
The production fallback body remains unchanged and runs against the actual application controller through a temporary method swap.
The first half of the run uses the compiled production method without that swap.

## Interpretation

The compatibility code preserves appearance as a scoped caller context, including during nested browser work.
The native evidence confirms that the fallback does not leave one browser's colors dependent on the peer's appearance.
The explicit restoration also preserves the caller context when a nested update fails.
I found no further abstraction or ownership defect that requires a production change.

## Environment and limits

- macOS 26.5.2, Xcode 26.6; Intel app under Rosetta.
- App SHA-256: `0e877e5a1576b932b6bedfb85770a918f266925f0cc844120cce0987a889f695`.
- The runner uses a copied app with disposable notes and preferences.
- Nested updates and exceptions are injected review schedules. They are not claims about a normal application event sequence.
- The fallback is forced on the current host. This does not establish runtime compatibility with an actual older macOS release.
- Compiler warnings concern the probe's modern appearance constants and a method declared in one category and generated in another. Both are supported by this host.
- Colors are checked through native controller and editor properties. This is not a screenshot comparison or a performance test.
- Production source files remained unchanged during this review.

## Proposed PR comment

Round 2 — Ousterhout engineering perspective, not authorship or endorsement: no new actionable findings.

The independent native probe passed 109 checks on the corrected app.
It nests one real browser's appearance update inside an opposite-appearance browser, across all User/System scheme combinations.
Both the compiled modern path and an extracted forced fallback restore the outer and original caller appearances, including after an injected nested exception.
Successful updates retain their own resolved palettes, and shared source attributes remain unchanged.

Evidence: `Tests/UserSchemeReview/round2/ousterhout/`.
The forced fallback runs on macOS 26.5.2; it does not replace testing on older macOS installations.
