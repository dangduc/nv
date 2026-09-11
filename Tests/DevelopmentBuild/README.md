# Development and release isolation

`run-tests.py` runs both compiled apps together in one disposable home.
It runs both apps again after normal termination.
The test uses original startup and persistence code from each executable.

## Run

Build `Notation Develop` and `Notation Release` into `build/DerivedData` with the Intel options in the repository guide.
From an active macOS desktop session, run:

```sh
python3 Tests/DevelopmentBuild/run-tests.py --output build/DevelopmentBuild
```

Use `--development-app` or `--release-app` for another build location.
The host sandbox can block AppKit process registration before startup.
The desktop test requires permission to run outside that sandbox.

The runner uses the root repository's `build/pr-review/gui.lock` across all worktrees.
Each run writes four logs, `results.json`, and two native window bitmaps to the output directory.
The runner deletes its disposable apps, data, and preference domains after the run.

## Coverage

The runner checks original bundle names, executable names, bundle identifiers, build flavors, and URL schemes before it copies either app.
The probe checks these behaviors:

- Original startup selects separate default notes folders.
- Application support uses the executable name, and the journal cache uses the bundle identifier.
- Only Development displays the `DEV` Dock badge.
- The two processes save different notes, list font sizes, editor background colors, and backup intervals.
- Each real backup package contains the exact note title and body from its own library.
- Both processes remain active together before either process can terminate.
- A fresh process reads the same paths, settings, notes, and backup content after relaunch.
- Development skips automatic legacy preference reads. Release retains its first-run legacy import attempt.
- Keychain lookup selects a separate Development service.
- Plain-text external editing uses separate temporary directories.

## Disposable state and limits

The copied apps retain their executable names and build flavors.
Each copy receives a unique test bundle identifier for its preference domain.
The test does not replace the app's path selection or library initialization methods.
Runtime class lookup also supports release executables that strip exported Objective-C symbols.

Injected functions redirect Cocoa user directories, the home directory, the temporary directory, and Carbon `FSFindFolder` results.
The two processes share these redirected base directories.
Thus the app must select its own distinct subdirectories.
The fixture lives under `build/` because the backup store rejects symlink ancestors such as `/var`.

The probe replaces legacy preference input with an empty dictionary.
It returns “item not found” from keychain lookups and blocks keychain writes.
It suppresses ODB initialization and delayed global UI actions, including hotkey registration.
The runner disables automatic update checks through launch arguments.

This test does not cover encrypted libraries, protected RAM disks, real keychain storage, custom backup destinations, Finder routing, or update delivery.
The [round-three complete-app probe](../DevelopmentBuildReview/round3/ousterhout/REVIEW.md) adds first-use custom backups and checks their payloads after relaunch.
It does not coordinate concurrent writes to a notes folder that the user deliberately shares between both builds.
The window bitmaps show disposable notes and visual settings, rather than the system Dock.
