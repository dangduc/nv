# Production app search probe

This probe uses the actual AppController, browser session, editor, library, and native search service.
It runs in a copied Intel app with disposable notes and a separate preferences domain.
A controlled completion gate delays publication to exercise pending actions deterministically.
It does not replace matching or controller methods with test doubles.

```sh
python3 Tests/FuzzySearch/UI/run.py --build-only
python3 Tests/FuzzySearch/UI/run.py --timeout 60
```

The first command compiles the injected probe without launching the app.
The second requires a Development app in `build/DerivedData` and an active desktop.
A busy desktop-test lock stops the runner before launch.
A timeout sends a kill signal without waiting indefinitely for a stalled Rosetta process.

The probe checks:

- Fuzzy title priority, overlapping note rows, and legacy Exact body matching.
- Shared storage, editing session, caret, and Undo identity when switching duplicate occurrences.
- Unique document targets for multiple selected occurrences.
- Saved mode and occurrence, legacy restoration, and deferred Reveal.
- Pending Return, obsolete zero results, model changes, and browser closure.
- Immediate highlight removal in both editors after shared character changes.

The Intel probe compiled without diagnostics on September 9, 2026.
Intel application startup is unavailable on this host. These UI assertions have not executed here.
