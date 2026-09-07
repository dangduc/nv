# Cached-note font regression

After building the Development app into `build/DerivedData`, run:

```sh
python3 Tests/Regression/fonts/run-probes.py
```

The test opens a temporary notes library in a copied app with separate preferences. Run with process-sandbox escalation when Rosetta cannot launch inside the sandbox. The runner serializes GUI access with `build/pr-review/gui.lock` and limits its app subprocess to 90 seconds.

Checks cover the hidden note model and cached editor font, reopening, the next edit, and notes with no cached session. A marked-text check verifies that refreshing sessions defers replacement and preserves the composition through commit.

The original failing probe remains in `Tests/ReviewEvidence/round1/torvalds/` as historical evidence.
