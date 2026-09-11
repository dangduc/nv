# Round 1: state and persistence review

Reviewed commit `2dbfd46` against base `bd74bf3`. This review uses a Kingsbury-inspired focus on state histories and failure boundaries.

## Finding: P2 — Separate the custom backup destinations by app flavor

Location: `Sources/Storage/NVBackupController.m:198` and `:204`.

Copy a library into a separate development notes folder, then select the same custom backup root in both apps. Both copies retain the same backup library UUID. The apps now keep duplicate-library claims in separate defaults domains, so neither process detects the other copy. The custom-root branch returns the selected root without an app namespace. Both destinations therefore resolve to `<selected root>/<same library UUID>`.

The executable fixture confirmed this path collision before and after process relaunch. Its control opened another physical copy in the same defaults domain; that copy correctly received a new UUID. The separate defaults domains expose the missing namespace for custom destinations.

This permits the two libraries to share a backup history and retention policy despite separate notes folders. Source inspection supports that consequence: `NVBackupStore` identifies ownership and snapshot membership by library UUID. This review did not execute retention deletion or prove data loss.

Use a separate development namespace under custom backup roots. Preserve the release destination for existing backups.

## Executed evidence

Command: `python3 -B Tests/DevelopmentBuildReview/round1/kingsbury/run.py`.

- H1 passed: concurrent processes used separate UUID defaults domains. Each retained its backup interval, alias bytes, and physical-library claim after relaunch.
- H2 reproduced: the two flavors produced the same custom destination for the copied library UUID. Both retained that collision after relaunch. The same-domain copy control renewed its UUID.
- Nine process commands completed. Each asserted that no `NSApplication` instance existed.

`runtime-output.log` contains the command results. `results.json` records the process history, reviewed commit, and resolved destinations.

## Scope and limits

The harness compiles verbatim selected production backup methods. It replaces only class type names and supplies small library/preference objects. It uses real Foundation bookmarks and `NSUserDefaults` processes. It does not launch the production app or exercise a GUI.

Only temporary directories and generated `org.nvalt.kingsbury-review.*` preference domains are used. The runner deletes those domains and directories. It does not access the release or development production preference domains, user notes, or the keychain. The persisted alias bytes are test values, not real folder aliases.

Keychain source review found that lookup, add, update, and delete use the flavor-selected service while retaining the library account ID. The existing runtime suite already intercepts those methods. This bounded review adds no independent native keychain dispatch evidence and makes no claim about keychain permissions or encrypted-library unlock behavior.

No production files were changed.
