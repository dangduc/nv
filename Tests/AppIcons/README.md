# App icon selection checks

Run these commands from the repository root on macOS:

```sh
python3 Tests/AppIcons/check-resources.py
python3 Tests/AppIcons/run.py
```

The resource check detects changes to the compiled catalog or its source inputs.
Use `--app /path/to/app` to also check the built app's icon keys and bundled resources.

The native probe creates three disposable app bundles with distinct icon settings.
The hybrid bundle must match the classic control before macOS 26 and the modern control on macOS 26 or later.
The two controls must produce different images, which prevents a generic-icon result from passing.

The probe checks two system APIs:

- `NSWorkspace.iconForFile:` resolves the app icon before launch, as Finder does.
- `NSApplication.applicationIconImage` supplies the running app's Dock icon.

The helper apps use `LSUIElement` and create no windows or Dock entries.
The probe removes all helper bundles when it finishes.
It retains PNG renders under `build/icon-selection/` for inspection.
Use `--catalog` and `--output` to check a regenerated catalog without replacing the committed resource.

The `App icon compatibility` workflow checks the committed and regenerated catalogs on macOS 15 and 26.
The main macOS build workflow checks catalog hashes and the resources in both app configurations.
