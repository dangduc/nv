### Round 1 contrarian review

- **P2:** All six bundled `Excruciatingly Useful Shortcuts` help files still
  advertise Command-[ / ], Option-Tab, Command-T/B/I/Y, and
  Command-Left/Right behaviors that this branch removes. Please update those
  shipped help notes to describe native source editing.
- **P3:** In all six localized XIBs, the status menu's **Format** submenu now
  starts with two adjacent separators before its only item, **Fix Text
  Encoding**. Remove the orphan separators.

Evidence: `python3 Tests/NativeEditingReview/round1/contrarian-a/run.py`
reproduces both findings across six localizations and confirms the removed
editor selector inventory. It also found that the XIB spelling-correction
state matches a fresh `NSTextView` on this macOS release. I did not automate
opening the status menu or exercising every stale shortcut.
