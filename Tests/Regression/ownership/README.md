# Editor ownership regression

Run on macOS with Xcode:

```sh
python3 Tests/Regression/ownership/run.py
```

The test compiles the current `LinkingEditor` deallocation method, its preferences assignment, and the `GlobalPrefs` singleton accessor. Foundation sentinels replace UI objects. It does not load nvALT or access notes or application preferences.

Closing the simulated editor must preserve borrowed preferences and nib outlets. The owned text finder must release its reference. Three mutation checks add incorrect borrowed releases. Another mutation removes the text finder release. Each variant must fail. Source guards also reject borrowed releases and missing owned releases.

This test checks reference ownership. Run the Cocoa integration suite after rebuilding to check real window and editor teardown.
