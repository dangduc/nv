# Round 2 — Torvalds perspective

This review uses a Linus Torvalds-inspired engineering perspective. It does not represent his authorship or endorsement.

No further actionable PR defect found.

I read all Round 1 reports and the completed Round 2 reports before this review.
The Round 1 appearance guard is corrected in `0fc7aca`.
This round independently checks the later editor fix for named colors that resolve outside the owning appearance.
The publishing agent wrote that editor fix.

The reviewed helper is `Sources/Editor/LinkingEditor.m:473`, `currentSearchHighlightAttributes`.
It retains the result inside the appearance scope and returns it autoreleased.
Its fallback restores the previous appearance in `@finally`.
Both range-publication methods use this helper.

The native probe passed **55 assertions**, including two library setup assertions.
The unchanged helper body also compiled for macOS 10.13 with availability errors enabled.
See [run.py](run.py), [prefix.h](prefix.h), [probe.inc](probe.inc), and [output.txt](output.txt).

The probe runs both the compiled modern helper and an extracted fallback against the actual editor and browser.
The extraction renames the method and forces the fallback choice. The fallback body remains unchanged.
The caller has a light appearance, while the native editor has a dark appearance.

The assertions establish these results:

- Each helper request calls the settings resolver exactly once, inside the editor appearance.
- The resolver receives the owning browser's dark selection and resolved background.
- A nil result remains nil and restores the caller appearance.
- A tracked dictionary survives the callback pool with a caller retain.
- The caller release destroys that dictionary exactly once. The helper retains no remaining ownership of that result.
- An injected resolver exception reaches the caller after appearance restoration.
- Direct and legacy range publication each install the expected opaque color blend.
- A nil direct-publication result clears the earlier direct and legacy decorations.
- The complete source attributes remain unchanged after every case.

The settings wrapper forwards ordinary color requests to the production resolver.
It substitutes nil, a tracked dictionary, or an exception only for the corresponding contract checks.
The tracked dictionary records its destruction without relying on approximate retain counts.

Command:

```sh
python3 Tests/UserSchemeReview/round2/torvalds/run.py
```

Result: exit 0.
Host: macOS 26.5.2, Xcode 26.6, Intel app through Rosetta.
App SHA-256: `3e8ebdc2258bd0d402e56066e6dd649ed7c277b4c6b05f95566a7e468df0dbf9`.

The runner uses a copied app, disposable notes, and an independent settings domain.
The fallback runs on this current host. It does not establish behavior on an actual older macOS installation.
The ownership check covers one tracked result type. It does not establish leak freedom for the application.
The probe checks synchronous range publication and native temporary attributes. It does not measure asynchronous search timing or screenshot pixels.
An initial fixture compile lacked the controller helper declaration. Adding its existing header corrected the fixture without a production change.
Production files remained unchanged during this review.
