# Source workflow regression checks

Run these checks after a Development build:

```sh
python3 Tests/Regression/source-workflow/run.py
```

The suite uses real AppKit controls in a copied application with isolated settings and temporary notes.
It checks source and viewer switching, Undo, selection, scroll, local syntax, peer windows, composition, stale requests, and window restoration.
It checks visible syntax captures, separate viewer scroll positions, and malformed saved presentation data.
It also checks that the hidden source editor rejects editing commands.
The suite blocks application network requests and uses a private pasteboard.
All preview fixtures contain local text without remote resources.

Set `NV_UI_ARTIFACTS` to an output directory to capture Source and Preview screenshots.
The captures use the native window image after the relevant view is ready.
