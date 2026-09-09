# Search persistence checks

The native fixture compiles actual bookmark, saved-search, last-search, and followed-link methods extracted from the application sources.
In-memory notes, defaults, and a table stand-in isolate these methods from the desktop and personal preferences.
The fixture does not duplicate the production serialization logic.

Run the checks:

```sh
python3 Tests/FuzzySearch/Persistence/run.py
python3 Tests/FuzzySearch/Persistence/run.py --sanitize
python3 Tests/FuzzySearch/Persistence/run.py --arch x86_64 --compile-only
```

Each of these negative checks must fail:

```sh
python3 Tests/FuzzySearch/Persistence/run.py --mutation drop-row
python3 Tests/FuzzySearch/Persistence/run.py --mutation legacy-fuzzy
```

The checks cover legacy Exact defaults, malformed metadata, distinct occurrences, dictionary round trips, and retained query whitespace.
They also cover mode-aware saved-search identity, repeated object assignment, nil-note cleanup, selected-occurrence scroll offsets, and followed-link stack order.
The followed-link fixture asserts forwarding through the asynchronous bookmark restoration hook. It does not emulate worker completion or browser rendering.

Native arm64 and sanitizer runs each passed 26 checks on September 9, 2026.
The fixture also compiled and linked for Intel with the macOS 10.13 target.
Both mutations failed at their intended assertions.
The four affected application sources passed Intel syntax checks with the application prefix header and existing Objective-C dispatch setting.

`SavedSearchesController.m` remains outside the application target.
Its restored header exposes its archive model. Its historical storage selectors remain declarations for the dormant controller.
The complete dormant source passes syntax checks with two existing-style delegate conformance warnings.
These checks do not activate that controller or restore its obsolete preference API.
