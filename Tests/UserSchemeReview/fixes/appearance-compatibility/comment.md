Addressed the Round 1 availability finding. `browserAppearanceChanged` now guards `performAsCurrentDrawingAppearance:` at macOS 11. Earlier systems retain, set, and restore `currentAppearance` with `@finally`.

The maintained compatibility check compiled the unchanged production method for macOS 10.13 with availability errors enabled. It then passed 16 checks with the fallback branch forced on this host. Those checks cover User/System updates, restoration after success and an injected exception, retained colors, and fixed schemes. Both negative controls failed as expected: the old 10.14 guard and restoration only after success.

Evidence: `Tests/UserSchemeReview/fixes/appearance-compatibility/`. This is a controlled branch simulation, not a run on an older macOS installation.
