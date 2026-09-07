# Native browser controls

The toolbar contains New Note, Preview, Note Actions, Sync Status, and Search or Create. Standard toolbar customization controls the visible items.

- Use Command-N to create a blank note and edit its title.
- Type in Search or Create to filter notes. Selection does not replace the query.
- If no note matches, press Return or click Create to create a note with that title.
- Edit the title or tags above the body. Return commits the edit. Escape cancels it.
- Drag the horizontal divider to resize the notes list. Each window saves its own height.
- Select Follow System Appearance in the color menu for automatic light and dark colors. Existing explicit colors and fonts remain available.

`probes.m` exercises these controls in the application with disposable notes and a separate preferences domain. `benchmark.m` compares query and drawing costs across builds. See `Tests/README.md` for the commands.

Live sync services, external editor applications, and macOS versions other than the test host require separate manual checks.
