### Round 2 contrarian review

**P3: Remove the surviving hidden tab-width preference and paragraph-style override.** `GlobalPrefs` still registers `NumberOfSpacesInTab`, exposes `numberOfSpacesInTab`, removes AppKit's tab stops, and builds a replacement interval from that value. This is residue from the deleted soft-tab/custom-indentation implementation and keeps a source-layout behavior outside `NSTextView` defaults.

The disposable app probe launched with `-NumberOfSpacesInTab 11`. The nvALT style used no tab stops and a 79.471-point interval; its next glyph landed at x=84.471 versus x=33.000 in a fresh plain `NSTextView`. Please remove the key, getter, and custom paragraph-tab builder and let AppKit supply paragraph tab layout.

Evidence: `python3 Tests/NativeEditingReview/round2/contrarian-a/run.py` passed 10 runtime checks plus 9 localized/static audit groups. It compiled all 18 relevant localized XIBs and checked Preferences, menu, plain-editor, formatted-import, and storage-format boundaries. I found no other actionable issue in those boundaries. I did not drive VoiceOver, keyboard-navigate Preferences, or execute every export operation.
