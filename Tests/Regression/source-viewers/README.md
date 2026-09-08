# Source viewers

Run the isolated renderer checks:

```sh
python3 Tests/Regression/source-viewers/run.py
```

The runner compiles an Intel Foundation executable with disposable converter copies.
It checks snapshot identity, Unicode, Markdown, Textile, direct HTML, and concurrent requests.
It also checks invalid output, helper failure, cancellation, process limits, and pipe drainage.
HTML fixtures cover passive styles, HTML5, SVG, disabled controls, and removed scripts.
The Markdown viewer treats TaskPaper markers as ordinary Markdown source.

From an active desktop session, run the inline viewer checks:

```sh
python3 Tests/Regression/source-viewers/run-viewer.py
```

The runner uses a temporary application, preferences domain, asset directory, and GUI lock.
It checks WK rendering, read-only controls, local asset scope, blocked remote assets, Find, and scroll restoration.
It also checks stale requests, provider changes, error states, and cancellation during closure.
No library or user notes are opened.

The viewer uses system libxml2 to preserve HTML5 elements while removing active content.
CSP prevents document scripts and remote resources on all supported systems.
On macOS 11 or later, WebKit also disables content JavaScript independently of native document queries.
Native Find and scroll queries have no script-message handlers or application bridge.
Native printing requires macOS 11 or later; the provider reports that capability explicitly.

Mode and note transitions capture DOM offsets asynchronously, with their call-time note and viewer identity.
The provider delays replacement navigation until these captures finish.
A loading request returns its own cached state rather than the previous document's offsets.
If WebKit does not reply within 0.5 seconds, the capture returns immutable cached state.
Closing a provider completes pending captures with cached state and prevents delayed callbacks from restarting navigation.
Synchronous application termination can still use the last cached state.

Transition fixtures scroll and switch immediately without waiting for the periodic state cache.
They cover rapid A → B → A changes, Source return, missing WebKit replies, late replies, and closure during capture.
