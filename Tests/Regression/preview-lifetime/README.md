# Preview and editor lifetime regression

After building the Development app into `build/DerivedData`, run:

```sh
python3 Tests/Regression/preview-lifetime/run.py
```

The runner copies the app, creates a random preferences domain, and opens a temporary notes library. It serializes GUI access with the other review runners. On Apple Silicon, run outside the process sandbox so Rosetta can launch the app.

The runner executes two cases. The blank-preview case opens and closes eight browser windows using real nibs. All eight browser controllers, editors, preview controllers, and WebViews must deallocate.

The rendered-preview case shows two different notes, exercises `Cocoa.log` with a fixed message, and closes all browsers. It then repeats four reopen/render/close cycles on the same library. All five additional browser controllers, editors, preview controllers, and WebViews must deallocate. The retained initial service owner and shared notes must remain usable.

Run one case with `--case blank` or `--case rendered`. Rendering removes the test injection variable from the app's environment before it launches the external markup helper.

Instrumentation only observes lifetime events and invokes the original methods. It does not release preview references, remove the script bridge, or repair application ownership. The runner times out without waiting indefinitely for an uninterruptible Rosetta child.
