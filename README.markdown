# nvALT — dangduc fork

nvALT is a macOS notes app with search and Markdown previews. This fork of [ttscoff/nv](https://github.com/ttscoff/nv) adds multiple windows and native macOS controls.

Every window keeps the notes list above the editor. All windows share one notes library.

![Light appearance with a white notes list, native toolbar, and separate title and tags](docs/screenshots/native-light.png)

## What changes in this fork

| Area | Upstream nvALT | This fork |
| --- | --- | --- |
| Windows | One main notes window. | Multiple windows share one library. Each window has its own search, selection, sort order, and scroll position. |
| Layout | Stacked or side-by-side panes. | The notes list always stays above the editor. Each window saves its divider height. |
| Controls | Custom window controls and a combined search/title field. | A native toolbar contains Search or Create. Separate fields edit the title and tags. |
| Search | The combined field also shows the selected title. | The search query stays visible after selection changes. An unmatched query offers an explicit Create action. |
| Appearance | Legacy window controls and color schemes. | Native macOS controls, automatic editor colors, and a white notes list in light and dark appearances. |

Saved side-by-side layouts restore as stacked panes. The fork retains Markdown, MultiMarkdown, and Textile previews, note links, tags, import/export, and custom editor fonts.

### Multiple windows

Each window can show a different note or search. Edits to the same note appear in all windows that show that note. Undo and Redo share the history for that note, including committed title and tag edits.

The app restores open windows and their saved views after a restart. A library change applies to all windows.

![Two windows share a library with independent garden and travel searches](docs/screenshots/multiple-windows.png)

### Native controls and appearance

The toolbar contains New Note, Preview, Note Actions, Sync Status, and Search or Create. Standard toolbar customization controls which items appear.

The title and tags sit between the list and the body. Tags use completion from the library. The editor supports system colors and custom colors. The notes list stays white, with optional pale alternating rows.

<details>
<summary>Dark appearance with a white notes list</summary>

![Dark toolbar and editor with the notes list still white](docs/screenshots/native-dark.png)

</details>

These screenshots use sample notes on macOS 13.7.8. Control appearance can differ across macOS versions.

## Use the app

| Action | Instruction |
| --- | --- |
| Open another window | Choose **Window > New Window**, or press **Command-Shift-N**. |
| Create a blank note | Press **Command-N**. Then enter the title. |
| Find a note | Type in **Search or Create**. Use **Command-J** or **Command-K** to move through the results. |
| Edit a search result | Select the note. Then press **Return**. |
| Create from a search | If no note matches, press **Return** or click **Create**. |
| Edit the title or tags | Edit the field above the body. Press **Return** to commit, or **Escape** to cancel. |
| Resize the list | Drag the divider between the list and the editor. |
| Use system colors | Select **Follow System Appearance** in the color menu. |
| Open a preview | Click **Preview** in the toolbar. |

## Build and run

This fork currently distributes source code. The [official nvALT download](https://brettterpstra.com/projects/nvalt/) contains upstream nvALT, without these fork changes.

The build requires full Xcode. Command Line Tools alone are insufficient. Bundled frameworks require an Intel build, so Apple Silicon Macs need Rosetta.

The command below passed on macOS 13.7.8 with Xcode 15.2 and the macOS 14.2 SDK. Other macOS and Xcode versions need separate checks.

1. Clone this fork:

   ```sh
   git clone https://github.com/dangduc/nv.git
   cd nv
   ```

2. If `SimperiumConfig.h` is absent, create it from the example:

   ```sh
   test -e SimperiumConfig.h || cp SimperiumConfig-example.h SimperiumConfig.h
   ```

   The placeholder supports local use without sync. Simplenote sync requires your own API key.

3. Build the Development app:

   ```sh
   xcodebuild -project Notation.xcodeproj -scheme 'Notation Develop' \
     -derivedDataPath build/DerivedData ARCHS=x86_64 \
     MACOSX_DEPLOYMENT_TARGET=10.13 CODE_SIGNING_ALLOWED=NO \
     GENERATE_PROFILING_CODE=NO OTHER_CFLAGS= WARNING_LDFLAGS= build
   ```

4. Quit any other nvALT build before the first run.
5. Run the app:

   ```sh
   open build/DerivedData/Build/Products/Development/nvALT.app
   ```

The build retains the upstream application identifier and can use existing nvALT settings and notes. The built-in updater still points to upstream. Updates to this fork require a new build from this repository.

## Development checks

After a Development build, run these commands from an active desktop session:

```sh
python3 Tests/run-multiple-windows-tests.py
python3 Tests/run-regression-tests.py
```

The suites use temporary notes and a copy of the app. They cover shared edits, Undo/Redo, window restoration, search, metadata, preview ownership, and appearance.

[Tests/README.md](Tests/README.md) describes focused checks and full-screen checks. [The review record](Tests/NativeUIReview/VALIDATION.md) lists results and limits. Live sync services and external editor apps need separate manual checks.

## Preview customization

1. Choose **Open Custom CSS Folder** from the Preview menu.
2. Edit `template.html` for the HTML structure.
3. Edit `custom.css` for the preview styles.

The preview also supports JavaScript in the template. Missing custom files use the bundled defaults.

## Contribute and credits

[AGENTS.md](AGENTS.md) describes the source layout, coding conventions, and pull request requirements. Reports about this fork belong in [dangduc/nv issues](https://github.com/dangduc/nv/issues).

nvALT comes from Brett Terpstra and David Halter. It builds on Zachary Schneirov's [Notational Velocity](https://github.com/scrod/nv) and [DivineDominion's MultiMarkdown fork](https://github.com/DivineDominion/nv).

The repository includes the [GNU General Public License, version 3](COPYING.txt). Bundled components retain their own license notices.
