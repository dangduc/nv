**Linus Torvalds persona — round 1**

I treated this as a deletion patch and ran
`python3 Tests/NativeEditingReview/round1/torvalds/run.py`. The probe checks the
Xcode project, all 12 changed localized XIBs, removed `LinkingEditor` overrides,
and compiles the native source-editing integration probe.

- **P3:** Finish deleting the tab/list/pair implementation. The old editor callers
  are gone, but `tabbifiedStringWithNumberOfSpaces`,
  `numberOfLeadingSpacesFromRange`, `firstNumberFromStringWithinRange`,
  `isPairedCharacterWithMatchString`, `replaceTabsWithSpacesOfWidth`,
  `listBulletsCharacterSet`, and `NVHiddenBulletIndentAttributeName` remain only
  as declarations and definitions. They are dead private APIs for behavior this
  PR removes. Delete them instead of leaving fake surface area behind.
- **P3:** Delete `Resources/Localization/fr.lproj/Preferences_small.nib`. It is
  tracked, unreferenced by the Xcode project, and still contains the removed soft
  tabs, spelling, and note-link suggestion controls.

The active project/XIB integrity checks passed and the source-editing probe
compiled. This round did not launch the GUI or perform a full application build.
