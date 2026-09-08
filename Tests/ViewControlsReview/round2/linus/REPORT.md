# Round 2: Linus Torvalds-inspired review

No introduced defect was established for PR #5 at `162c872` against base `b27af28`.
This independent review uses a correctness-focused perspective. It does not represent Linus Torvalds or his endorsement.

The native probes completed 327 invariant checks and 64 scenarios on macOS 26.5.2 (25F84), with Xcode 26.6 (17F113).
All commands returned zero. Focus observations remain separate from those invariant checks.

The control probe uses only commands that exist in both app versions.
Each run covers two repetitions of three Search histories at 480-point and 780-point content widths.
The histories use the existing toolbar, remove and restore Search, or hide and restore the toolbar.
The probe records Search focus after 350 milliseconds, then records body focus immediately and after 500 milliseconds.
It never calls a new View action.

| App | Language | Invariant checks | Histories | Search focus losses | Delayed body focus losses |
| --- | --- | ---: | ---: | ---: | ---: |
| Base | English | 45 | 12 | 0 | 3 |
| Base | Chinese | 45 | 12 | 0 | 3 |
| Head | English | 45 | 12 | 0 | 3 |
| Head | Chinese | 45 | 12 | 0 | 3 |

All four runs lost body focus in exactly the same three 480-point histories.
These were repetition 0/history 1, repetition 1/history 0, and repetition 1/history 2.
The immediate body focus succeeded. After 500 milliseconds, the window itself became the first responder.
All 780-point histories retained body focus.
The matching base results establish that this delayed focus behavior predates the PR.
The control did not reproduce the earlier single Chinese Search-focus failure, so its cause remains unresolved.

The base app comes from the PR #4 build at `d5fc585`.
The local diff found no changes between that commit and `b27af28` in `Sources`, `Resources`, `Config`, or `Notation.xcodeproj`.
The head app is the frozen round-one build at `build/ViewControlsReview/round1/nvALT.app`.
The Search restoration and focus methods themselves are unchanged in the PR.

The separate head probe passed 147 checks across all eight header combinations in both Source and Preview.
It uses actual menu dispatch and native field-editor Tab commands.
Tab from Title reaches visible Tags or the current body. Tab from Tags reaches the current body.
The Source/Preview command and its return focus the correct body in every combination.
These actions preserve the exact note title and source characters.

The review covered `AGENTS.md`, `architecture.md`, and the production diff.
It also covered menu construction, validation, action routing, the field-editor delegate, and key-view links.
No changed line receives a finding or priority because the evidence establishes no introduced defect.

Run the controls:

```sh
python3 Tests/ViewControlsReview/round2/linus/run-control.py \
  --app build/ViewControlsReview/round1/nvALT.app --label head
python3 Tests/ViewControlsReview/round2/linus/run-control.py \
  --app build/ViewControlsReview/base/nvALT.app --label base
```

Run the header navigation probe:

```sh
python3 Tests/ViewControlsReview/run-probe.py \
  --app build/ViewControlsReview/round1/nvALT.app \
  --probe Tests/ViewControlsReview/round2/linus/key-chain.inc \
  > Tests/ViewControlsReview/round2/linus/key-chain-output.txt 2>&1
```

The evidence files are `control-base-en.txt`, `control-base-zh.txt`, `control-head-en.txt`, `control-head-zh.txt`, and `key-chain-output.txt` beside this report.
Every native run used desktop escalation, a copied app, disposable notes, unique defaults, and the shared `build/pr-review/gui.lock`.
The runner removed the injected-library environment variable before helper processes started.

The focus observations cover one operating system and two window widths. They do not establish the cause of every native toolbar transition.
The key-chain probe covers forward Tab navigation and menu commands. It does not cover accessibility navigation or every input method.
No production files, commits, or PR comments changed during this review.
