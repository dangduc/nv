# Round 3 UX: saved settings and restoration

No additional actionable finding from this process-history check.
The frozen production revision is `47d18f43cadb1a2eeeed9c7fbe379795c76faae7`.

The probe passed 74 assertions across ten processes.
Release first saved its settings and two browser-state records.
Development then started with a fresh domain and saved different values.
Both flavors retained their own values after relaunch.
Development then changed its settings and replaced two browser records with one.
Release retained its original settings and records.

The final phase deleted only the generated Development domain.
Development returned to its two registered standard settings and had no saved browser records or custom color archives.
Release again retained all original values.

The standard settings are Word Count and clickable links.
The custom settings are light and dark editor background colors.
The browser records contain distinct queries, search modes, note markers, source selections, and source scroll states.
The production coordinator dispatched the expected records to the corresponding recording browsers after each relaunch.

## Reproduction and implementation

Run from the frozen worktree with access to macOS preference services:

```sh
python3 Tests/DevelopmentBuildReview/round3/ux/run.py
```

The command passed and wrote `results.json`.
The initial sandboxed run did not synchronize its generated preference domain.
The same probe passed with desktop service access.
This constraint does not establish a production settings failure.

The runner compiles verbatim production `GlobalPrefs` setters and getters and the coordinator's window save/restore methods.
Real `NSUserDefaults`, `NSColor` archives, and separate process launches provide persistence.
The fixture replaces browser objects and records preference callbacks.
It registers two standard values that the runner compares with the production initializer.
It does not run the complete preference initializer.

The two temporary bundles retain flavor metadata from the built Development and release products.
The runner checks their original bundle identifiers before it assigns unique `org.nvalt.round3.ux.*` domains.
Both processes use one temporary preference home through `CFFIXED_USER_HOME`.
The runner deletes only its generated domains and temporary files.
The probe uses Intel code with the macOS 10.13 deployment target and runs through Rosetta.

## Limits

The browser records are fixtures.
The check covers coordinator persistence and dispatch, not actual window creation or visual restoration.
Preference callbacks are recorded but do not redraw an editor.
No complete application, GUI, notes library, keychain operation, or installed application settings enter this probe.
Runtime menu naming and physical identification of both running apps remain outside this check.
The existing application probe separately asserts the DEV Dock badge.
This reviewer changed only `Tests/DevelopmentBuildReview/round3/ux`.
