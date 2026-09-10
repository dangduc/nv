# Runner acceptance checks

These tests guard the result decisions in the maintained backspace and highlight runners. All compiler and application subprocesses use controlled results. The suite does not launch nvALT.

Run from the repository root:

```sh
python3 -B -m unittest discover -s Tests/SourceBackspaceReview/fixes/oracles -v
```

The tests execute the complete SourceBackspace Python runner with a disposable, nonexecutable app fixture. They extract the maintained HighlightBounds `run_case` function and its assertion map to skip native compilation.

The checks accept full success and intended mutation assertions. They reject partial success, loader errors, signals, incorrect assertions, and unknown mutations. The SourceBackspace checks also verify environment isolation, explicit negative-control mode, and timeout handling.

`output.txt` records the 16 passing tests. `manifest.json` identifies the tested runners and maps each expected mutation assertion to its saved native log. Those logs came from earlier runs; this validation does not rerun or replace them.
