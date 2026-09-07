# Architecture

nvALT is a Cocoa application written mainly in Objective-C, with C utilities and manual memory management.
This fork supports multiple browser windows over **one shared notes library**.
Each window keeps the notes list above the editor.

This document describes the current implementation. See [README.markdown](README.markdown) for features and build instructions.

## Runtime ownership

The application owns the library and coordinates windows. Browser sessions hold window-specific search state.
Editing sessions share live text between windows that display the same note.

```mermaid
flowchart TD
    A["NVApplicationController"] --> L["NotationController: shared library"]
    A --> B
    A --> E["NVNoteEditingSession: cached per note UUID"]
    L --> N["NoteObject: model and undo manager"]
    E --> N
    subgraph Window["Each browser window"]
        B["AppController"] --> S["NVBrowserSession"]
        B --> V["LinkingEditor and its layout manager"]
        B --> P["PreviewController"]
    end
    S -.-> L
    V -.->|shared text storage| E
```

Solid arrows show ownership or control. Dashed arrows show access to shared state.

| Component | Responsibility |
| --- | --- |
| [NVApplicationController](NVApplicationController.m) | Owns the library, browser controllers, and editing-session cache. Routes application actions and library notifications. |
| [AppController](AppController.m) | Owns one browser window, its views, selection, and preview controller. The initial instance also handles legacy application services. |
| [NVBrowserSession](NVBrowserSession.m) | Holds one window's query, matching notes, visible rows, sort order, and list-preview cache. |
| [NotationController](NotationController.m) | Owns notes, labels, storage, journal recovery, and sync services. |
| [NoteObject](NoteObject.m) | Stores a note's UUID, title, body, tags, dates, file identity, sync metadata, and undo manager. |
| [NVNoteEditingSession](NVNoteEditingSession.m) | Owns shared `NSTextStorage`, committed snapshots, and deferred external content. Coordinates body and metadata edits. |
| [GlobalPrefs](GlobalPrefs.m) / [NotationPrefs](NotationPrefs.m) | Manage application settings and library-specific settings, respectively. |

## Startup and command routing

[main.m](main.m) enters `NSApplicationMain`.
The localized `MainMenu.xib` creates the initial `AppController`.
That controller installs `NVApplicationController` as the application delegate.
The coordinator delegates existing startup work to the initial controller, then configures menus, services, hotkeys, and window restoration.

Additional windows load a localized `BrowserWindow.xib` and attach to the existing library.
They do not open another database or start another set of sync services.
The initial controller remains retained after its window closes because it still owns application settings and status UI.

Window commands usually reach the active browser through the coordinator.
View actions use `NVControllerForView()` to find their owning browser.
During a forwarded library call, the coordinator records the originating browser.
Library reveal callbacks use that browser, falling back to the active browser outside the call.
Application settings and lifecycle commands still use the initial controller.

One compatibility detail matters when reading older code: `AppController`'s `notationController` variable now holds an `NVBrowserSession`.
Use `browserSession` for window state and `sharedNotationController` for the library.
The session forwards remaining library methods through `performLibraryInvocation:fromBrowser:`.

## Search and window state

Each browser session filters the shared notes into its own result set.
Search terms match titles, bodies, or tags without case sensitivity. Every term must match somewhere in the note.
The parser supports quoted phrases.

Incremental search can reuse previous matches when a query becomes more restrictive.
Library changes invalidate those candidates.
During a library refresh, the selected note can remain visible even when an edit makes it stop matching.
That retained row is excluded from the search candidate cache.

Selection, editor scroll, list scroll, divider height, and column layout belong to the browser.
Application settings can supply defaults or update shared display choices.
Do not move query state into the library or reuse another window's list-preview cache.

## Shared editing and Undo

The coordinator creates editing sessions on demand and caches them by note UUID.
Each editor attaches its own layout manager to the session's text storage.
Windows therefore share live text while keeping separate selections and display state.
`NoteObject` holds the committed model content. Disk writes occur later.

A body edit follows this path:

1. `LinkingEditor` changes the shared text storage.
2. `AppController` asks the editing session to commit the change.
3. The session registers Undo and writes the content to `NoteObject`.
4. The note schedules persistence and sends `NVNoteContentsDidChangeNotification`.
5. The session sends `NVNoteEditorDidChangeNotification`. The coordinator refreshes affected editors and browser lists.

The session's write guard prevents its own model notification from reloading the content recursively.
The note's undo manager also records title and tag changes.
Body editors disable Cocoa's automatic Undo registration to avoid a second history.

Input-method composition requires special handling.
While any attached editor has marked text, the session defers body commits and holds incoming model snapshots.
After composition ends, it compares local and external changes against the committed snapshot.
Non-overlapping changed ranges can merge.
Overlapping changes preserve external content in a separate note with an `(external changes)` title suffix.
The original note keeps the local content.

External body snapshots discard stale body Undo entries while retaining metadata history.
Snapshot updates use a bounded text diff to preserve selections in other editors.
If the diff exceeds its work limit, the session applies one replacement range.

When switching notes, detach only that editor's layout manager and attach it to the new storage.
Do not use `replaceTextStorage:`: it moves all layout managers attached to the old storage.
Editing sessions remain cached until library replacement or application termination.

## Persistence and external changes

`NotationController` owns the write queue and journal lifecycle.
[NotationFileManager](NotationFileManager.m) handles file operations.
[NotationDirectoryManager](NotationDirectoryManager.m) handles directory monitoring and reconciliation.
Storage can use a single database or separate note files, according to `NotationPrefs`.

`NoteObject` marks changed content dirty and requests a write.
The library batches writes using a delay after the latest change and a separate timer during continued editing.
It writes note files when required and appends journal records through [WALController](WALController.m).
[FrozenNotation](FrozenNotation.m) serializes the library snapshot and its settings.
`flushAllNoteChanges` drains pending writes and stores that snapshot atomically.
A visible editor change does not mean the disk write has finished.

[NotationSyncServiceManager](NotationSyncServiceManager.m) integrates service changes into the library.
[SyncSessionController](SyncSessionController.m) manages service sessions, scheduled pushes, status, and pending-change waits.
File changes and sync updates reach editors through the note model and editing sessions.
Windows observe shared sync status rather than owning separate service connections.

## Browser UI and previews

[AppController_BrowserUI.m](AppController_BrowserUI.m) builds the native toolbar, title and tag fields, and `NSSplitViewController` layout.
The localized nibs supply reusable views and connections.
The split view uses `setVertical:NO`: its horizontal divider keeps the list above the body.
Automatic macOS window tabbing is disabled.

The notes list uses a white background and an explicit Aqua appearance in both light and dark modes.
The editor can follow system appearance or use configured colors.
[LinkingEditor](LinkingEditor.m) applies display colors and search highlights through each editor's layout manager.
An appearance change must not rewrite shared note content.

The search field holds a query independently of the selected note's title.
Title and tag controls commit through the editing session and retain the original target note during an edit.
New Note creates a blank note. Creation from search uses the query as the title.

Each browser owns a [PreviewController](PreviewController.m) with a separate preview window.
Browser-scoped notifications request delayed preview updates.
The controller converts markup to HTML and renders it with the legacy WebKit `WebView`.
Custom `template.html` and `custom.css` files override bundled defaults.
Preview output is separate from the shared note body.

## Library replacement, closure, and restoration

Before replacing the library, the coordinator finishes browser edits and closes cached editing sessions.
It closes the old library's resources, attaches every browser to the new library, and starts its sync services.
`closeAllResources` stops file monitoring and sync, flushes pending changes, and removes the journal after a successful flush.

Closing a browser finishes edits, detaches its editor, and closes its preview.
Additional browsers also unregister their observers. The initial controller remains the bridge to application services.
The application can remain open without visible browsers, depending on the quit-on-close setting.
Termination saves window state, commits editing sessions, and uses the existing application shutdown and sync-wait paths.

[AppController_MultipleWindows.m](AppController_MultipleWindows.m) serializes browser state.
`NVApplicationController` stores it under the `NVBrowserWindows` defaults key and restores up to 20 windows.
Saved state includes the query, sort, selected note UUID, selection range, scroll positions, frame, columns, and divider height.
Restoration checks selection bounds and converts old side-by-side layouts into a vertical stack.

## Working on the architecture

Most source files live at the repository root.
Objective-C categories divide existing controllers across files such as `AppController_Importing.m` and `NotationDirectoryManager.m`.
Add new source files and resources to [Notation.xcodeproj](Notation.xcodeproj).

Preserve manual `retain`/`release` ownership.
When changing window lifetime, check observer removal, delayed callbacks, nib ownership, and shared text attachments.
Keep library I/O and sync startup outside browser sessions.
Add regression checks for changes to ownership, command routing, and restoration.

[Tests/README.md](Tests/README.md) explains the Cocoa integration suites and focused regression checks.
They use a copied app and temporary notes in an active desktop session.
Live sync services and external editor applications require separate manual checks.

The [macOS workflow](.github/workflows/macos.yml) builds and packages an unsigned Intel app, then tags successful builds on `master`.
It does not run the desktop integration suites.
See [Tests/CI/README.md](Tests/CI/README.md) for artifact validation and tagging rules, and [AGENTS.md](AGENTS.md) for contributor conventions.
