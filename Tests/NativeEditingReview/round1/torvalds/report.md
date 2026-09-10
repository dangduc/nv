# Round 1 — Linus Torvalds review

I reviewed the native editor simplification as a deletion patch: removed code must
have no live callers, no dead compatibility surface, and no resource references
left behind. `run.py` checks the Xcode project, all 12 changed localized XIBs,
the removed `LinkingEditor` overrides, and the compile-only integration probe.

## Findings

### P3 — Finish deleting the private tab/list/pair machinery

The old editor call sites are gone, but seven private helpers remain as declaration
and implementation pairs with no production callers:

- `tabbifiedStringWithNumberOfSpaces:tabWidth:usesTabs:`
- `numberOfLeadingSpacesFromRange:tabWidth:`
- `firstNumberFromStringWithinRange:isInRange:`
- `isPairedCharacterWithMatchString:`
- `replaceTabsWithSpacesOfWidth:`
- `listBulletsCharacterSet`
- `NVHiddenBulletIndentAttributeName`

The probe found each token only in its header and implementation under
`Sources/Utilities/NSString_NV.*` or `Sources/Editor/AttributedPlainText.*`.
These APIs implemented the soft-tab, list-continuation, auto-pair, and hidden
bullet-indent behavior deleted by this patch. Keeping them leaves exactly the
sort of misleading private surface this cleanup is supposed to eliminate.
Delete their declarations and implementations.

### P3 — Delete the orphan French legacy preferences nib

`Resources/Localization/fr.lproj/Preferences_small.nib` is tracked and still
contains `Soft tabs`, `checkSpellingButton`, and `autoSuggestLinksButton`. The
Xcode project does not reference `Preferences_small`, so it cannot affect the
running application. It is nevertheless stale repository UI that describes
settings this patch removes. Delete the orphan nib directory.

## Evidence executed

```text
python3 Tests/NativeEditingReview/round1/torvalds/run.py
```

The structural checks passed for the branch diff, project references, removed
`LinkingEditor` overrides, active localized XIBs, and removed active UI outlets
and actions. `Tests/SourceEditing/run.py --compile-only` also passed.

## Validation limits

This round is a structural deletion audit plus a compile-only native integration
probe. It does not launch the GUI, exercise input methods, or rebuild the full app.

