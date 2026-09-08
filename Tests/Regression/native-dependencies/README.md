# Native dependency checks

Build the Development app, then run:

```sh
python3 Tests/Regression/native-dependencies/run.py
```

The runner uses a copied app, a separate preferences domain, and disposable notes.
It blocks sync requests and redirects clipboard writes to a private test pasteboard.

The checks cover login, index, changes, note creation, update, and deletion JSON.
They also cover Unicode link ranges, email and file URLs, wiki links, disabled imports, and updater menus.

Source windows must leave the inline viewer unallocated until the user selects Preview.
The suite checks that sharing, sticky previews, generated-source tabs, and script templates are absent.
It also checks inline WebKit ownership, independent browser modes, source preservation, and viewer disposal during browser closure.

Use `--compile-only` to compile the harness without launching a desktop app.
