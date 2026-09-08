# Native dependency checks

Build the Development app, then run:

```sh
python3 Tests/Regression/native-dependencies/run.py
```

The runner uses a copied app, a separate preferences domain, and disposable notes.
It blocks network fetches and redirects clipboard writes to a private test pasteboard.
It never invokes the sharing service.

The checks cover login, index, changes, note creation, update, and deletion JSON.
They also cover Unicode link ranges, email and file URLs, wiki links, disabled imports, and updater menus.
Popover checks use the real nib views and verify content, dismissal, reopening, and browser teardown.

To capture the result popover, set `NV_DEPENDENCY_SCREENSHOTS` to an absolute PNG path.
