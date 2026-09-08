# Preview and editor lifetime regression

Build the Development app into `build/DerivedData`, then run:

```sh
python3 Tests/Regression/preview-lifetime/run.py
```

The runner copies the app, creates a random preferences domain, and opens a temporary notes library.
It uses the GUI lock shared by the other desktop runners.
On Apple Silicon, run outside the process sandbox so Rosetta can launch the app.

The source case opens and closes eight browser windows through their native interfaces.
All eight browser controllers and editors must deallocate.
The windows must allocate zero viewer providers and zero `WKWebView` instances.
Model changes then exercise observer removal while the shared library remains open.

The rendered case displays two notes in separate inline viewers and checks that the application script bridge is absent.
It closes all browsers, then repeats four reopen, render, and close cycles on the same library.
All five additional browser controllers and editors must deallocate.
All six viewer providers and `WKWebView` instances must deallocate, including the initial window's provider.
The retained initial service owner, shared preferences, and source notes must remain usable.

Run one case with `--case blank` or `--case rendered`.
Use `--compile-only` to compile the harnesses without launching a desktop app.
Rendering removes the test injection variable before it launches markup helpers.

Instrumentation only counts lifecycle events and invokes the original methods.
It never releases application-owned references, clears delegates, removes callbacks, or repairs ownership.
The runner applies a timeout without waiting indefinitely for an uninterruptible Rosetta process.
