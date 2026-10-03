# Preview compatibility references

The HTML files are exact outputs captured from the checked-in Intel MultiMarkdown
4.7.1 and Org helper at master commit `89e07a03d91bcf973d78c1a3d40793f359ea7548`.
`previews.json` records the helper, command arguments and input for each output.
CI compares rebuilt arm64 helper output against these references before staging
the helpers into the app build. The fixtures exercise metadata, full-document
output, compatibility mode, tables, footnotes, Unicode, code, Org heading links,
and directives that must remain inert.

Regenerate a reference only when a deliberate converter behavior change requires
it. A different CPU architecture should not require a changed reference.
