### Round 1 contrarian review

**P3 — Source editors still start with non-native Smart Copy/Paste behavior.** The isolated app probe reports `smart insert/delete editor=0 native=1`: each decoded `LinkingEditor` starts disabled, while a fresh plain `NSTextView` in the same process starts enabled. The new first-responder `toggleSmartInsertDelete:` command works, but the initial state does not match the native default promised by the simplification.

Please add `smartInsertDelete="YES"` to the `LinkingEditor` nodes in every localized `MainMenu.xib` and `BrowserWindow.xib`, and cover that decoded state in the source-editing regression.

Evidence: `python3 Tests/NativeEditingReview/round1/contrarian-b/run.py` parsed/compiled the changed localized XIBs and completed 28 injected runtime checks before intentionally exiting 2 for this mismatch. Keyboard/paste/drag implementations are inherited; retired defaults are inert; native menu actions reach the active editor; rich paste strips foreign presentation attributes. The drag result is based on implementation identity rather than a synthesized mouse gesture; IME, Accessibility input, and cross-process Services were not exercised.
