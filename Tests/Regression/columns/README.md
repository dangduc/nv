# Browser column regression checks

After the Development build, run:

```sh
python3 Tests/Regression/columns/run-probes.py
```

The Cocoa runner uses a copied app, temporary notes, and a separate preferences domain. Run outside the restrictive process sandbox.

The 22 checks cover independent browser widths and order, property-list round trips, layout switches, inactive layout settings, and malformed values. Restoring settings respects the global column visibility preference.

Browser state now records column settings for both layouts. Old browser states without this field remain readable. This change does not migrate column settings from the single-window Cocoa autosave preferences.
