# Native browser controls

The toolbar contains Search or Create, which fills the available width beside the window controls. The window hides its title.
Note commands remain available through menus. The toolbar ignores saved layouts from the previous toolbar.
The checks restore an old toolbar configuration and verify that action icons remain absent.

- Use Command-N to create a blank note and edit its title.
- Type in Search or Create to filter notes. Selection does not replace the query.
- If no note matches, press Return or click Create to create a note with that title.
- Edit the title or tags above the body. Return commits the edit. Escape cancels it.
- Drag the horizontal divider to resize the notes list. Each window saves its own height.
- Select Follow System Appearance in the color menu for automatic editor colors. The notes list always uses system light and dark colors.

`probes.m` exercises these controls in the application with disposable notes and a separate preferences domain. `benchmark.m` compares query and drawing costs across builds. See `Tests/README.md` for the commands.

External editor applications and macOS versions other than the test host require separate manual checks.
