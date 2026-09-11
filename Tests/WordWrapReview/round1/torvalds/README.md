# Round 1: typesetter correctness and minimality

This review covers commit `4b049709b2cecc6eac80514586ccacc119d12802`, relative to `b6a5696`.
It uses a correctness and minimality perspective inspired by Linus Torvalds.
It does not represent his review or endorsement.

The probe links the production `NVSourceTypesetter.m` directly.
The runner extracts the production glyph delegate from `LinkingEditor.m` without changes.
The probe creates disposable Cocoa text systems without windows.
It does not open nvALT or change application preferences.

Run the source-style checks and the extended paragraph matrix:

```sh
python3 Tests/WordWrapReview/round1/torvalds/run.py --arch arm64
python3 Tests/WordWrapReview/round1/torvalds/run.py --arch x86_64
```

Run the negative control:

```sh
python3 Tests/WordWrapReview/round1/torvalds/run.py --negative-control
```

The negative control removes the custom typesetter.
It must fail the condition that fitting words remain whole under the common source paragraph style.
The runner records that expected failure as a successful negative control.

The matrix uses Menlo 18, three container widths, seven paragraph configurations, five alignments, and three source fixtures.
Its 315 cases cover Latin words, Hebrew words, and tabs.
Every Latin word fits the available width in each case.
The source-style assertions cover zero indents with natural, left, right, and center alignment.

The geometry oracle uses native word layout with the same production glyph delegate.
It compares positions only when both layouts select the same complete line range.
The probe also records the previous character layout for every case.
The oracle does not repeat the production boundary algorithm or Core Text measurements.

The runner writes full snapshots, summaries, and native-action results to `build/WordWrapReview/round1/torvalds/`.
The summary includes the commit and SHA-256 digest of the production implementation.
The report in `findings.md` separates source behavior from paragraph styles without a verified source-app path.

This probe does not cover older macOS versions, native key events, editing, performance, or every Unicode script.
The parent review owns the complete application build and desktop suites.
