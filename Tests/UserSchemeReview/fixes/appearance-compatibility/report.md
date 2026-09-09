# Fix for the Round 1 availability finding

The fix guards `performAsCurrentDrawingAppearance:` at macOS 11.
Earlier systems use `currentAppearance` to apply colors in the browser appearance.
The method retains the previous appearance and restores it in `@finally`.
An exception from the color update still reaches the caller after restoration.

Production change: `Sources/Browser/AppController_BrowserUI.m`, in `browserAppearanceChanged`.

The separate maintained check consists of:

- [compatibility.py](../../../Regression/user-schemes/compatibility.py)
- [compatibility.m](../../../Regression/user-schemes/compatibility.m)

The runner extracts `browserAppearanceChanged` from the production source.
It first compiles the unchanged method for macOS 10.13 with availability warnings treated as errors.
It then substitutes a Boolean for the availability expression to force the earlier-system branch.
The remaining method body remains unchanged.

The fixture uses native `NSAppearance` and `NSColor` objects on macOS 26.5.2.
Small controller, settings, window, and table stand-ins isolate the appearance scope.
The source method resolves colors through those stand-ins and the actual AppKit APIs.

The run passed the compilation check and 16 runtime checks:

- User and System apply the owning appearance during the update.
- Both schemes restore the previous appearance after success and an injected exception.
- Both resolved colors survive the callback autorelease pool.
- Fixed schemes leave the appearance unchanged.
- Successful updates invalidate the table. Failed updates propagate the exception first.

Both negative controls failed at the intended boundary:

- The old macOS 10.14 guard failed the compiler availability check.
- Restoration only after success failed the exception-restoration assertion.

Command:

```sh
python3 Tests/Regression/user-schemes/compatibility.py --negative-controls
```

[Recorded output](output.txt) contains the successful checks and expected negative-control failure.
The outer runner returned zero because both negative controls failed as expected.

This evidence simulates an earlier-system branch on the current host.
It does not establish runtime behavior on an actual macOS 10.13, 10.14, or 10.15 installation.
The full application build and desktop checks remain the responsibility of the publishing task.
The original Round 1 evidence remains unchanged.
