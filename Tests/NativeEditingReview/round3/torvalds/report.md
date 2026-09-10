# Round 3 — Linus Torvalds review

I reviewed `4265d28` as a final deletion and target-consistency patch. The
round-two fixes removed the hidden tab-width override, unsupported finder
branches, the password generator, and the extra `NSTextFinder` retain. The old
preference tokens are absent from production source, and the source-editing
integration probe still compiles.

## Findings

### P1 — Remove the deleted cursor image from the Xcode target

`Resources/Images/IBeamInverted.png` is deleted, but
`Notation.xcodeproj/project.pbxproj` still contains both PBX objects and both
membership entries for it (lines 154, 406, 978, and 1997 at this revision). A
fresh unsigned Intel Development build reaches the Resources phase and fails:

```text
error: Build input file cannot be found: '.../Resources/Images/IBeamInverted.png'.
** BUILD FAILED **
```

This blocks the PR. Delete the `5CF96DD6...` build-file object and Resources
phase entry, and delete the `21DB407D...` file-reference object and Images group
entry.

### P3 — Finish deleting source-editor residue

`LinkingEditor` no longer implements `isContinuousSpellCheckingEnabled`,
`readablePasteboardTypes`, or `acceptableDragTypes`, but both order files still
name all three class-specific symbols. `Notation.launchorder` is passed to the
linker by `SECTORDER_FLAGS`; `Notation.freqorder` is the checked-in companion
profile. Remove those six stale lines.

`highlightRangesTemporarily:` is also declaration-and-definition-only. The new
search-highlighting path installs `NSArray<NSValue *>` ranges through
`setSearchHighlightRanges:`; no production caller uses the old CFArray helper.
Delete its header declaration and implementation.

## Evidence executed

```text
python3 Tests/NativeEditingReview/round3/torvalds/run.py
```

The runner invokes two independent code probes. `project_probe.py` derives the
deleted paths from the branch diff and inventories remaining Xcode references.
`source_probe.py` checks removed preference tokens, unsupported deployment
branches, finder ownership, order-file symbols, and caller-free helpers. The
runner also performs a fresh Xcode build in a temporary Derived Data directory
and compiles the source-editing integration probe. `output.txt` contains the
filtered build failure.

## Validation limits

The failing Resources phase prevents this run from proving a complete linked
application at this revision. The probe compiles the editor integration target,
but I did not launch the application or run the desktop GUI suites.
