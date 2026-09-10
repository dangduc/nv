Linus-style round 3 found one blocker and one cleanup item, both reproduced by executable probes.

- **P1:** `Resources/Images/IBeamInverted.png` was deleted, but `project.pbxproj` still has all four PBX object/membership lines. A fresh unsigned Intel Development build fails in `CopyPNGFile` with `Build input file cannot be found`. Remove the `5CF96DD6...` build-file/phase entries and the `21DB407D...` file-reference/group entries.
- **P3:** finish the deletion: remove the six `LinkingEditor` order-file lines for the no-longer-overridden `isContinuousSpellCheckingEnabled`, `readablePasteboardTypes`, and `acceptableDragTypes`; remove the declaration-and-definition-only `highlightRangesTemporarily:` CFArray helper.

Evidence: `python3 Tests/NativeEditingReview/round3/torvalds/run.py` derives deleted paths from the branch diff, audits source/order references and ownership/compatibility residue, reproduces the Xcode resource failure in fresh Derived Data, and compiles the source-editing integration probe. Full report and filtered build output are under `Tests/NativeEditingReview/round3/torvalds/`.
