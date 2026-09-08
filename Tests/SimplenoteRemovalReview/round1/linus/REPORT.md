# Round 1: integration and simplicity review

Perspective: Linus Torvalds-inspired attention to build integration and concrete failure modes. This is an analytical lens, not participation or endorsement.

Reviewed commit: `f38a8cb3f1e5f74c57cfe5e8d5791f364201f1cb`, against `9693356`.

No actionable introduced defect found in this scope.

The removal is connected through the project and packaged application. All six preference interfaces compile and instantiate with the production owner class. Their retained connections match the previous interfaces.

Evidence:

- [integration.py](integration.py) resolves Xcode groups, variant groups, and source/resource/copy build phases. It checks that all 331 resolved inputs exist and belong to the checkout.
- It checks the executable and package independently: four retired Objective-C classes, the sync-manager category methods, and 16 deleted sync images are absent. Direct IOKit and SystemConfiguration framework dependencies are absent.
- The four classes and a sync-manager category method are present in the retained pre-removal app, which provides a positive control. Each locale also has an in-memory negative control: a dangling outlet target makes the same connection resolver fail.
- It checks 102 compiler dependency records for any remaining requirement on the removed sync configuration. CI no longer copies that configuration.
- It compares every action and outlet in all six preference XIBs against the previous `designable.nib` sources. Retained connections keep the same targets and IDs. All removed connections belong to retired sync controls.
- [checks.inc](checks.inc) and [prefix.h](prefix.h) load each compiled localized nib with a real `NotationPrefsViewController`. The probe checks connected owner outlets, implemented actions, native control targets, tab identifiers, and initialized storage-format choices. It traverses both tab contents, including the unselected Security tab.
- Results: **710 integration assertions** and **304 native assertions** pass. The native total includes the runner's three temporary-library setup assertions. Logs: [integration.log](integration.log), [native.log](native.log).

Relevant production locations: `Notation.xcodeproj/project.pbxproj:181`, `:835`, `:1902`, `:2225`; `Sources/Preferences/NotationPrefsViewController.m:44`; `.github/workflows/macos.yml:32`.

Reproduce from the repository root after building and copying the reviewed app to `build/SimplenoteRemovalReview/round1.app`. The integration probe also expects the retained pre-removal app at `build/SyntaxFlickerReview/fix.app`:

```sh
python3 Tests/SimplenoteRemovalReview/round1/linus/integration.py
NV_REVIEW_INTEGRATION_MANIFEST="$PWD/Tests/SimplenoteRemovalReview/round1/linus/manifest.json" \
  python3 Tests/ViewControlsReview/run-probe.py \
  --probe Tests/SimplenoteRemovalReview/round1/linus/checks.inc \
  --prefix Tests/SimplenoteRemovalReview/round1/linus/prefix.h \
  --app build/SimplenoteRemovalReview/round1.app
```

Environment: macOS 26.5.2; Xcode 26.6 (17F113); x86_64 Development app. Reviewed executable SHA-256: `d61aea6619f6c4322efac164d7409ac131aa0ce2a8760d874850c34443331ede`.

The positive-control executable has SHA-256 `ee8e9ca27c99d55ff867afabd49e75c12f5548f49ac93dc733f514f477cac365`. It is the retained source-syntax-flicker fix app from before Simplenote removal, not a new build of the exact comparison commit.

Probe corrections: the first draft treated the sync-manager category as a class. Review caught this, and the final probe checks its actual category methods. Adding the old-app positive control also showed that `TitlebarButton` was already absent from that executable, so the final probe makes no binary-removal claim for that class. Both corrections affect the evidence, not production code.

Limits: This probe verifies connections and initialization, not every preference action's behavior. It does not establish compatibility with older macOS/Xcode versions or reproduce a complete clean build. The package and compiler records came from the build prepared by the parent task. SDK/framework inputs are intentionally outside the tracked-file closure. The test uses temporary notes and a disposable app copy; it keeps test-only nib owners alive until process exit.
