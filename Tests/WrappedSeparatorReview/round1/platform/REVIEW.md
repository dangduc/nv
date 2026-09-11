# Round 1: AppKit compatibility and paragraph layout

Reviewed frozen production `9e6c8dd6adc058e7044f2c562532af97dd4e63d4` against `75d6f4269d5c3f0ff2d3df392659ccf95bc1482b` for PR 30.
No actionable platform finding arose from this bounded review.
The changed classifier is in `Sources/Editor/LinkingEditor.m:298–315`.

The runner extracts both complete glyph callbacks and the candidate typesetter through `git show`.
The compiled probe uses the actual callbacks and complete `NVSourceTypesetter` implementation.
`results.json` records source hashes, compiler commands, deployment metadata, and runtime results.

## Compatibility audit

Both builds passed with `-Werror=unguarded-availability` and `-Werror=unguarded-availability-new`.
The Intel build targets macOS 10.13, and the arm64 build targets macOS 11.0.
`otool -l` reported those exact minimum versions in the executable load commands.
The current SDK declares both new Foundation queries without a later availability requirement.
These queries are `whitespaceAndNewlineCharacterSet` and `rangeOfComposedCharacterSequenceAtIndex:`.

Both executables ran on macOS 26.5.2 (25F84), with Xcode 26.6 (17F113).
Rosetta ran the Intel executable.
The deployment checks do not establish runtime compatibility with macOS 10.13, macOS 13, or any other older release.

## Paragraph, font-size, and adjacency evidence

Each architecture passed 1,406 assertions across 18 fixture combinations.
The fixtures use prose, one text attachment, or a tab beside a source space.
Menlo sizes are 9 and 27 points.
The paragraph variants use defaults, indents with paragraph/line spacing, and right alignment with a line-height multiple.

All six prose combinations matched native word-wrap line geometry and glyph positions within 0.01 points.
Five prose combinations differed from the baseline, so the native comparison detected the changed separator behavior.
All six tab combinations retained the baseline geometry.
All fixture combinations retained UTF-16 glyph mappings, control-glyph properties, source characters, and source attributes.
All attachment combinations retained the same native attachment dimensions.

## Attachment observations and limits

An initial assertion required complete native geometry equality for attachment fixtures.
That assertion failed for all three 9-point attachment cases on both architectures.
The baseline also differs from native geometry in those cases.
For default and right-aligned paragraphs, both production revisions split the same following word beside the attachment.
The indented case also has an attachment-related used-rectangle difference.

The final attachment assertions cover mappings, control properties, dimensions, and source preservation.
They do not claim complete geometry equality for rich text.
The application disables rich text and graphic imports at `Sources/Editor/LinkingEditor.m:68–69`.
The evidence does not establish a newly reachable product defect in this synthetic attachment path.
`initial-native-reference-results.json` preserves the first failed comparison.
The two architecture observation files retain all final baseline, candidate, and native geometry.

Font-size changes provide metric variation, not an actual zoom or Retina display test.
The probe creates no `NSApplication`, window, or GUI session.
It does not exercise pixels, screen scaling, accessibility, the full editor lifecycle, or actual user notes.
No production files, preferences, keychain items, commits, or PR comments changed.

## Reproduction

Run from the repository root:

```sh
python3 -B Tests/WrappedSeparatorReview/round1/platform/run.py
```

Each compilation, runtime process, and binary inspection has a 45-second timeout.
The runner deletes its temporary extracted sources and executables after completion.
