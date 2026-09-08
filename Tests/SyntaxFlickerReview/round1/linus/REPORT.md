# Round 1: correctness and simplicity

This review uses a Linus Torvalds-inspired perspective. It does not represent his participation or endorsement.

No actionable defect was found in the reviewed change.

The reviewed production revision is `65e1608ff4e9977ec2d7a09297739152f9cfc935`, compared with base `8cd2c95`.

## Evidence

[probe.m](probe.m) compiles the production highlighter with the pinned Tree-sitter grammars. It uses native `NSTextStorage`, two layout managers, and text containers with widths of 150 and 600 points.

The probe forces glyph generation and full layout before and after edits. It performs 24 edit histories for each of JSON, HTML, and Markdown:

- Four bursts of Unicode prefix insertion, surrogate-pair deletion, combining-sequence replacement, emoji ZWJ replacement, and multiline shortening.
- One coalesced replacement and deletion using `beginEditing` and `endEditing`.
- Whole-document replacement with a short source, deletion to empty, and insertion after the empty parse completes.

For single edits, an independent array models the expected temporary attribute at every UTF-16 position. Existing attributes must move with surviving characters. Inserted characters must have no old capture. Both layouts match this model before reparsing.

For the coalesced edit, the probe checks an unchanged suffix outside the aggregate edited range. TextKit may discard temporary attributes inside that range.

The probe then compares each completed display against a separate parser instance. It checks all positions, including gaps between captures. There are 27 completed source states and 54 layout comparisons.

The boundary-checking layout manager records every syntax attribute addition and removal. None occurs while the storage reports character processing. Capture ranges and generated glyph-to-character ranges remain within the current source. Syntax attributes never enter persisted storage attributes.

[output.txt](output.txt) records a successful native run: **72 edit histories, 354,727 assertions, and zero unsafe temporary attribute mutations**. Most assertions repeat bounds checks across character positions; this count does not represent independent test cases.

## Negative control

[check-mutation.py](check-mutation.py) creates an isolated implementation that invalidates display permission on every character edit. The production file stays unchanged.

[mutation-output.txt](mutation-output.txt) records the expected native exit status 1 at the first insertion:

> FAIL: Unicode prefix insertion: preceding revision remains displayable

This control demonstrates that the probe rejects the earlier display invalidation behavior. It does not merely verify eventual parser output.

## Reproduction

From the repository root:

```sh
python3 Tests/SyntaxFlickerReview/run-parser-probe.py \
  --probe Tests/SyntaxFlickerReview/round1/linus/probe.m
python3 Tests/SyntaxFlickerReview/round1/linus/check-mutation.py
```

The successful run used macOS 26.5.2, Xcode 26.6, and an Intel binary under Rosetta.

## Limits

This review checks TextKit display attributes and layout geometry. It does not measure screen pixels, frame timing, marked-text input, or the editor's color delegate. It does not establish behavior on older macOS releases.

The edit sequences are deterministic. They do not exhaust arbitrary Unicode edits, malformed UTF-16, parser cancellation schedules, or controller lifecycle changes. The parser acts as the final display oracle; this review does not assess grammar correctness.
