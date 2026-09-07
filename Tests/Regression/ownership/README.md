# Editor ownership regression

Run on macOS with Xcode:

```sh
python3 Tests/Regression/ownership/run.py
```

The test compiles the current `LinkingEditor` deallocation method, its preferences assignment, and the `GlobalPrefs` singleton accessor. Foundation sentinels replace UI objects; binding teardown is a no-op. It does not load nvALT or access notes or application preferences.

Closing the simulated editor must preserve borrowed preferences, nib outlets, and substring references. Owned find objects must release their references. Five mutation checks add the incorrect releases back, one at a time, and require each variant to fail. Source guards also reject borrowed releases and missing owned releases.

This test checks reference ownership. Run the Cocoa integration suite after rebuilding to check real window and editor teardown.
