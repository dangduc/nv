# Source analysis tests

Run `python3 Tests/SourceAnalysis/run.py` after changing background word or link analysis.
This standalone executable opens no notes or application windows.
It compiles the production scheduler and link methods with an Intel deployment target of macOS 10.13.

The fixtures compare worker word counts with Cocoa's existing scripting word ranges.
They check URLs, email, file references, wiki links, and Org target restrictions.
A controlled worker barrier checks immutable source capture, 500 replaced requests, stale results, and owner destruction.
The main run loop continues while the worker is blocked.
The barrier changes timing only; it calls the production decorator after release.

Results go to `build/SourceAnalysis/output.txt`.
These checks cover the worker protocol and extraction rules.
Run the source-editing and desktop regression suites to cover live TextKit, Undo, composition, and browser integration.
