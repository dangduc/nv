# Preview and editor lifetime regression

After building the Development app into `build/DerivedData`, run:

```sh
python3 Tests/Regression/preview-lifetime/run.py
```

The runner copies the app, creates a random preferences domain, and opens a temporary notes library. It serializes GUI access with the other review runners. On Apple Silicon, run outside the process sandbox so Rosetta can launch the app.

The test opens and closes eight browser windows using real nibs. Deallocation instrumentation counts browser controllers, editors, preview controllers, and the WebViews assigned by the nibs. All eight of each must deallocate. Shared preferences must remain usable, and the shared note must retain its contents.

Instrumentation only observes lifetime events and invokes the original methods. It does not release preview references or repair application ownership. The runner times out without waiting indefinitely for an uninterruptible Rosetta child.
