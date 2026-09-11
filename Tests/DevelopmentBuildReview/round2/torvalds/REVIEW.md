# Round 2: correctness and minimality

This review uses a Torvalds-inspired engineering perspective. It is not a review by Linus Torvalds.

No new actionable finding arose at commit `3a3dc4fb7194b5ea7189295a7bbd17393bb32038`.
The bounded native probe passed on arm64 and x86_64 through Rosetta.
The host used macOS 26.5.2 (25F84) and Xcode 26.6 (17F113).

## Hypothesis 1: the lazy prefix correction changes scan output or ranges

The runner extracts three frozen production scan methods:

- Release baseline: `bd74bf3e9e655fc69b5724fb7638f23a2f971f54`.
- Before the correction: `2dbfd4621077d6dec8b1195cb5002e29179cdfaa`.
- Current correction: `3a3dc4fb7194b5ea7189295a7bbd17393bb32038`.

The probe also uses the production bracket helper, percent-escape method, and identity header.
Only scan selector names change. An observation wrapper counts scheme calls and delegates to the actual identity helper.
The runner compares current production files against the frozen commit and records their hashes.

Eight short strings cover combining accents, emoji, reserved URL characters, nested brackets, empty brackets, edge whitespace, newline interruptions, and an unfinished link.
Every valid UTF-16 subrange enters the comparison, including zero-length ranges and ranges inside surrogate pairs.
This produces 3,723 range cases per process.

The corrected scan matches the previous scan for every URL value and attribute range.
Its output also matches the release baseline after only the Development scheme prefix changes back to `nvalt`.
Release and missing-flavor runs require no prefix normalization.
All source characters and nonlink attributes remain equal.
Every generated link stays inside the requested scan range.

Six additional cases independently decode the generated URL component through Foundation.
They recover the exact accented, decomposed, emoji, Indic, Chinese, and reserved-punctuation titles.
The generated URLs retain the `find` command without a query or fragment.

## Hypothesis 2: lazy lookup loses metadata behavior or still repeats work

Each architecture runs four temporary bundle fixtures: Development, copied Development with a different identifier, release, and missing flavor metadata.
All eight native processes pass 54,017 assertions each.
Development keeps `nvalt-dev` after the identifier changes.
Release and missing flavor metadata use `nvalt`.

Each process observes 3,307 linkless scans and 416 scans with links.
The corrected scanner makes zero identity calls for each linkless scan and one for each scan with links.
The previous scanner makes 467 calls across those same cases.
This is a call-count check, not a timing claim.

The local lazy variable removes repeated lookup without a permanent identity cache or another owner.
The executed comparisons found no need for additional abstraction at this boundary.

## Reproduction and limits

Run from the repository root:

```sh
python3 Tests/DevelopmentBuildReview/round2/torvalds/run.py
```

The adjacent `results.json` contains commit identities, source hashes, and all eight process summaries.
Generated source, binaries, logs, and detailed summaries remain in `build/DevelopmentBuildReview/round2/torvalds/`.
Each compile or native process has a 45-second timeout.
The runner deletes its temporary bundle fixtures.

The probe creates no NSApplication, opens no URL, and changes no preferences, notes, keychain items, or production files.
It does not exercise the complete source-analysis pipeline, URL click routing, Launch Services, a live library, or older macOS versions.
Its range cases are valid NSString ranges. They do not establish handling of out-of-bounds caller input.
Baseline comparison preserves existing scanner behavior. It does not prove a general wiki grammar or arbitrary-title encoding policy.
The custom-backup namespace issue belongs to the independent Ousterhout review and is outside this probe.
