# Round 2: platform and native backup store

Reviewed frozen production commit `3a3dc4fb7194b5ea7189295a7bbd17393bb32038`.
No new actionable findings arose from these two hypotheses.
The review changed no production files.

The runner passed 80 native assertions across both flavors on arm64 and x86_64.
The host ran macOS 26.5.2 with Xcode 26.6.
Rosetta ran the Intel executable.
`results.json` records each result and the source and metadata hashes.

## Hypothesis 1: built metadata disagrees with runtime behavior

The runner copied each existing built Info.plist without changes into a temporary executable bundle.
The probe used the identity header from the frozen commit.
The runtime flavor agreed with the bundle identifier and product name.
The runtime note scheme matched an advertised scheme in the built URL metadata.
Both flavors passed on both architectures.

The build metadata did not change in the Round 2 fixes.
This check used the existing build products and did not repeat compilation of the full app.
The probe executable replaced the app executable only inside its disposable bundle.

## Hypothesis 2: the writer recreates an unavailable custom root

The probe compiled the complete backup store from the frozen commit.
Each flavor first published an archive through the native store into an existing custom root.
The Development control included its namespace directory before publication.
The probe then moved its disposable root to make the captured path unavailable.

Publication, retention, and plaintext deletion each rejected the unavailable root with `ENOENT`.
None recreated the captured path.
The retained directory still contained one readable snapshot with the exact original archive bytes.
Both flavors passed on both architectures.

This check covers the store contract after a custom root exists.
It does not cover the known first-use namespace failure or the controller preflight that another reviewer reported.
It does not simulate an actual volume unmount or filesystem race.
The archive bytes were disposable opaque data, without archive decoding.

The probe used Foundation without a GUI or Launch Services registration.
Its imports contained no keychain or `NSUserDefaults` references.
It accessed no user notes, preferences, or keychain items.

## Reproduction

Run from the repository root:

```sh
python3 -B Tests/DevelopmentBuildReview/round2/platform/run.py
```

The runner requires both built products and Rosetta on Apple Silicon.
It deletes its temporary source copies, executables, app bundles, and archive directories after the run.
