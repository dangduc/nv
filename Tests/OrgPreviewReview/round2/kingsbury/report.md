# Org preview review, round 2: fragment navigation and retained state

This review uses a Kyle Kingsbury-inspired perspective on observable state and recovery.
It does not represent Kyle Kingsbury.

## P2: Capture the current scroll position after a heading-link click

Location: `Sources/Preview/PreviewController.m:284–286`.

The fixed Org links navigate to their headings in a real `WKWebView`.
However, immediate state capture rejects the new scroll position because fragment navigation changes `document.baseURI`.
The provider compares that value with its original document URL, which has no fragment.
It returns cached offsets instead of the current offsets.

The new native probe reproduces this sequence:

1. Display the `Notebook()` fixture in `probe.m` as an Org preview.
2. Activate its `Starred target` link through the real DOM.
3. Let WebKit accept and complete the same-document fragment navigation.
4. Call `captureViewerStateWithCompletion:` immediately, before the periodic state timer updates its cache.
5. Compare the captured offset with the actual `window.scrollY`.

The relevant source structure is:

```org
* Contents
[[*Release plan][Starred target]]

Opening paragraph 0.

Opening paragraph 1.

* TODO Release plan
:PROPERTIES:
:CUSTOM_ID: release-plan
:END:
Release body.
```

The executable fixture has additional links and 55 opening paragraphs so that the target requires scrolling.
It is fully specified in `Notebook()`, with no external note data.

The observed target position is **2,540 pixels**, but the captured state contains **no `scrollY` value**.
The logged `document.baseURI` ends with `/#release-plan`.
The provider's captured base URL ends with `/`.
The equality check rejects those offsets despite both URLs identifying the same document.

Expected behavior: an immediate capture retains the actual heading position, within two pixels.
This mismatch can lose the position during a prompt Source, viewer, or note transition before the 200 ms timer supplies newer cached offsets.
The probe directly demonstrates the wrong capture result. The transition consequence follows from the provider's restoration contract.

Compare document identity with only the fragment removed.
Retain the remaining scheme, host, path, query, generation, and presentation checks.
Keep the executable capture assertion as a regression gate.

This provider code is unchanged from base commit `f3a8abb`.
The new heading-link support exposes the existing behavior through ordinary Org navigation.

## Other evidence

An initial version passed **146 checks** before the immediate-capture assertion was added.
It used two native windows and the actual Org helper, production renderer, and production preview controller.
The navigation subclass observes policy decisions and then calls the production policy without changing its decision.

The passing checks cover these paths:

- Starred, exact, custom-ID, Unicode, generated-ID, and duplicate-heading links reach the expected heading.
- WebKit reports real link activation, permits the fragment, and scrolls the target to the viewport.
- Every heading receives a distinct document ID.
- Navigation in one window leaves the peer's position unchanged.
- Two providers retain separate scroll and Find state through a note/viewer change and source replacement.
- A delayed export writes the exact displayed generation after a note change, with matching anchors and encoded Unicode fragment targets.
- Navigation and state operations preserve both immutable source generations.

The final probe retains these checks and adds immediate state capture after each heading navigation.
It currently exits with status 1 after **24 passing checks and one failed assertion** at the first heading link.
The failure does not invalidate the earlier navigation checks, but it blocks a clean final run.

## Reproduction and snapshot

Run this command from the preview worktree in an active desktop session:

```sh
python3 Tests/OrgPreviewReview/round2/kingsbury/run.py
```

The runner holds the common GUI lock and uses a disposable app and export path.
The [initial output](initial-output.txt) records the 146-check run.
The [failure output](failure-output.txt) and [failure metadata](failure-metadata.json) preserve the failing gate and input hashes.
`output.txt` and `metadata.json` record the latest run.

The reviewed snapshot is commit `4467e7a7251ff3846c6d255db3bd64f465fda6b2` with the fixed heading-link working changes identified by the metadata hashes.
The helper SHA-256 is `dc5c563e75589ed615bc9faaad465f093ba180ac9c1b6baa3c4b2d874123fcba`.
All recorded production inputs remained unchanged during the run.
The host runs macOS 26.5.2 with Xcode 26.6 and Intel code under Rosetta.

## Limits

Link activation uses the native host's DOM call to `click()`, not a physical mouse event.
The real WebKit navigation delegate receives `WKNavigationTypeLinkActivated` and performs the fragment navigation.
The two providers receive immutable snapshots directly, without shared editing sessions or browser controllers.
The export panel is a test double. Conversion, sanitization, document display, and the file write remain real.
The probe does not establish complete Org navigation semantics, browser IME behavior, or operation on macOS 10.13.
No production files changed for this review.
