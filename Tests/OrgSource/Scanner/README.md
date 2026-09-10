# Patched Org scanner checks

Run `python3 Tests/OrgSource/Scanner/run.py` from the repository root.
The contract probe compiles the patched production scanner for Intel and arm64.
Each architecture passes 108 checks for serialization, decoding, state preservation, counter bounds, and worker isolation.
The arm64 probe also runs with AddressSanitizer and UndefinedBehaviorSanitizer.
The adapter probe compiles the production highlighter with one substituted parse call and passes six checks.
It injects a failure status after the real parser processes ordinary Org text.
This injection checks plain-source fallback, parser disposal, recovery, and isolation from JSON analysis.

The contract fixtures target the documented local format and compile only the patched scanner.
They do not run upstream code or construct a crashing note.
No app is launched. The macOS deployment targets do not prove execution on those older systems.

The full source analysis suite remains `python3 Tests/OrgSource/run.py`.
