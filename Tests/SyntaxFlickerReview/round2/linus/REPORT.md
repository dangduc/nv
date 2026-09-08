# Round 2: attribute edits and fallback correctness

This review uses a Linus Torvalds-inspired perspective. It does not represent his participation or endorsement.

No actionable defect was found in the reviewed change.

The reviewed production revision is `65e1608ff4e9977ec2d7a09297739152f9cfc935`, compared with base `8cd2c95`. Review evidence at `6e6f04e` does not change production code.

## Evidence

[probe.m](probe.m) compiles the production highlighter and pinned Tree-sitter grammars. It uses native `NSTextStorage` and two layout managers.

The Markdown, HTML, and JSON fixtures each have text containers of 160 and 500 points. The probe forces native layout for these small sources.

Each syntax runs nine bounded histories:

- Change the font, link, foreground color, and background color while captures are current. Generation and capture positions stay unchanged. No delayed reparse occurs.
- Make the same attribute changes after a character edit. Existing captures remain displayable and provisional. Attribute edits do not advance the source generation.
- Replace the entire attributed string with identical characters and different attributes. AppKit reports one character-edit generation. Fresh captures become current in both layouts.
- Change to an unsupported syntax while a character edit is pending. This immediately revokes provisional display permission. The completed result has no stale captures.
- Restore the supported syntax and compare its display with an independent parser.
- Replace the source with more than 524,288 UTF-16 units. The completed length-budget fallback clears all captures in both layouts.
- Restore a small source and verify complete highlighting recovery.
- Replace the source with `x`, an isolated high surrogate, and `y`. Native storage preserves these three UTF-16 units. The completed display has no captures.
- Restore a small valid source and compare its display with an independent parser.

Two additional histories exercise the display-operation budget. A JSON array produces exactly 3,000 parser captures. Across two layouts, this exceeds the 4,096-operation limit. The completed display clears all captures. A subsequent small JSON source recovers current highlighting in both layouts.

Every completed comparison preserves the exact attributed source. Syntax captures never enter persistent storage attributes. The instrumented layout manager checks capture bounds and rejects temporary capture writes during character processing.

[output.txt](output.txt) records **957 assertions across 29 bounded histories, with zero unsafe capture writes**. Repeated capture-bound assertions contribute to the total. This is not a count of independent cases.

## Negative control

[check-mutation.py](check-mutation.py) creates an isolated highlighter that processes attribute-only edits as character edits. The production file stays unchanged.

[mutation-output.txt](mutation-output.txt) records the expected native exit status 1 at the first attribute-only transaction:

> FAIL: attribute-only changes do not obsolete source analysis

The script succeeds only when the native probe fails at this assertion.

## Reproduction

From the repository root:

```sh
python3 Tests/SyntaxFlickerReview/run-parser-probe.py \
  --probe Tests/SyntaxFlickerReview/round2/linus/probe.m
python3 Tests/SyntaxFlickerReview/round2/linus/check-mutation.py
```

Both commands ran on macOS 26.5.2 with Xcode 26.6 and an Intel binary under Rosetta.

## Limits

This probe checks capture attributes, generation state, source attributes, and native layout. It does not test the editor's color delegate, screen pixels, physical input, or marked-text behavior.

AppKit accepted the isolated surrogate and produced six bytes during UTF-16 conversion. Therefore, this run does not exercise the parser's lossless-encoding-failure branch. It verifies a safe plain display and later recovery for this one malformed source.

The fallback checks cover source length, display operations, and an unsupported syntax. They do not force parser deadlines, the query match limit, or the maximum capture count. Large fallback fixtures do not undergo complete glyph layout.

The independent parser provides an oracle for completed capture placement. This review does not validate the grammars themselves or establish behavior on older macOS releases. No fixture failure occurred in the successful production probe.
