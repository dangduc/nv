# Closure check: Org heading scroll capture

The round 2 finding is resolved in the inspected working change.
The unchanged reviewer gate independently passed **167 checks**.
After the starred heading click, the captured and actual scroll positions both equal **2,540 pixels**.
All seven immediate-capture checks pass, including the encoded Unicode fragment after source replacement.

The fix removes only the fragment from both document-base strings before the existing comparison.
It preserves the scheme, asset-scope host, path, query, and existing comparison behavior.
It does not change generation checks, presentation identity, capture ordering, or timeout handling.
Literal `#` starts the removed fragment. Encoded `%23` remains part of the compared document identity.

The closure run used the original `run.py` and `probe.m` without changes.
It compiled the production snapshot, renderer, and provider with the actual helper in a disposable native app.
The existing native navigation, independent window state, source replacement, and displayed-document export checks also passed.

The [independent output](verified-output.txt) and [metadata](verified-metadata.json) record this run.
The metadata contains stable production and test-gate hashes.
The provider SHA-256 is `e786f468b82d7ae45c59adb3aed5123bcaa6dc3b757145ead9b219e90b79436a`.
The snapshot is commit `415cf6920bd5c74bc3911829431f3dcff7c4acb2` plus that provider change.
The run used macOS 26.5.2, Xcode 26.6, and Intel code under Rosetta.

The original failure artifacts and the author's separate fixed-run artifacts remain unchanged.
This targeted closure check does not add a review round or extend the original probe's coverage.
The original report's limits still apply, including DOM-initiated activation and standalone providers without browser controllers.
No production files changed during this closure review.
