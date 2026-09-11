# Round 2 UX and workflow review

No additional actionable finding from these bounded checks.
The reviewed production revision is `3a3dc4fb7194b5ea7189295a7bbd17393bb32038`.

## Executed evidence

The first check extends round one's recording harness with production percent escaping and dictionary query encoding.
It uses the actual note-link, wiki-link, and editor click methods.
Both Development and release passed 72 checks each.

Four Unicode titles cover accented Latin text, a decomposed accent, an emoji sequence, and Hebrew text.
The wiki attributes cover the exact source title.
Ordinary clicks send the original URL to the owning controller.
Command-click retains the active scheme and preserves the complete title and wiki source through query encoding.
Five copied-note cases include an empty title.
All copied URLs retain the active scheme, decoded title, and 16-byte UUID.
Empty source and an empty wiki target remain unchanged and unlinked.

The second check compares current installation documentation with built app metadata and production notes-folder constants.
The app names, preference domains, notes-folder names, URL schemes, and quoted launch commands match.
Both README and architecture documentation describe the Development subfolder inside a custom backup destination.
That text describes the intended destination layout.
It does not establish first-use directory creation.
Ousterhout's known round-two finding owns that creation failure, so this probe does not duplicate it.

## Reproduction

```sh
python3 Tests/DevelopmentBuildReview/round2/ux/run.py
```

The command passed and wrote `results.json`.
The probe compiles for Intel with the macOS 10.13 deployment target and runs through Rosetta in two temporary bundles.
The runner reuses the extractor and recording collaborators from `round1/ux`.
Temporary bundle metadata comes from the current built products.
The runner deletes temporary bundles after the run.

## Limits

The probe creates no application object, real editor, notes library, defaults domain, keychain item, or GUI.
The owning controller records the URL without interpreting it or creating a note.
The UUID fixture uses Foundation base64 encoding, as in round one.
Title escaping and dictionary query encoding use production implementations.
These Unicode fixtures do not cover all reserved punctuation in Command-click parameters.
LaunchServices dispatch, actual import behavior, runtime menu identity, and user-selected shared notes folders remain outside this review.
This reviewer changed only `Tests/DevelopmentBuildReview/round2/ux`.
