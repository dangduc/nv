# Round 1 review: configuration and legacy boundaries

Reviewed commit `2dbfd46` against `bd74bf3` from an Ousterhout-inspired engineering perspective.
The focus was configuration consistency, complexity at legacy boundaries, and ownership.

No actionable findings.

`NVAppIdentity.h` gives callers one source for the runtime flavor decision.
The two build configurations provide matching bundle metadata.
Existing classes continue to own their storage, import, and keychain operations.
The change does not add a second library owner or a new lifecycle coordinator.
The automatic legacy-import guard runs before reading legacy preferences or discovering old files.

## Executable evidence

Ran `python3 -B Tests/DevelopmentBuildReview/round1/ousterhout/run.py` successfully.
The checked-in probe tests these hypotheses:

1. Both built apps have the intended identities, executable names, URL registrations, Services entries, and localized names.
2. The production URL helper agrees with the primary scheme registered by each built app.
   Changing a copied bundle's identifier preserves the runtime flavor and URL scheme.
3. The production default-directory method selects a different notes directory for each flavor.
   Failed parent lookup prevents child creation. Both failure paths preserve their error codes.

The compiled directory probe uses the actual production method, with filesystem operations intercepted.
The runner checks its undefined symbols to ensure that real folder lookup and keychain operations are absent.
The four runs cover both flavors with original and changed identifiers.
The expected `-123` log messages exercise the failed-parent-lookup branch.

Also ran `python3 -B Tests/DevelopmentBuild/runtime/run.py` successfully.
That existing probe covers intercepted keychain lookup, addition, modification, deletion, password-buffer cleanup,
offline restore, external-editing directory names, and automatic legacy import.
It covers development, release, and missing-flavor metadata.

Results are in `output.log` and `runtime-output.log` beside this report.

## Limits

These probes do not exercise Launch Services delivery, Services invocation, Dock rendering, or a live encrypted library.
They do not open either complete app or inspect personal notes, preferences, or keychain items.
Built-bundle checks used the existing products in this worktree's `build/DerivedData` directory.
No production files were edited during this review.
