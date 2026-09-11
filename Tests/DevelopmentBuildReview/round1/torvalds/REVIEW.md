# Round 1: correctness, minimality, and native APIs

This review uses a Torvalds-inspired engineering perspective. It is not a review by Linus Torvalds.

The reviewed production commit is `2dbfd4621077d6dec8b1195cb5002e29179cdfaa`, against `bd74bf3` for PR 29.
No actionable findings arose in the examined boundaries. The review made no production changes.

The evidence ran on macOS 26.5.2 (25F84), with Xcode 26.6 (17F113).
Both arm64 and x86_64 probes passed. Rosetta ran the x86_64 probe on this arm64 host.

The native checks cover two integration boundaries:

- `NSPropertyListSerialization` parses the actual Xcode project as an OpenStep property list.
  Its configuration agrees with both built bundles for product names, identifiers, signatures, document ranks, and build flavors.
  `NSBundle` resolves the executable path that contains a space and returns the expected runtime identity.
- `CFBundleGetPackageInfo` returns separate creator codes: Development `4e764476` and release `4ea06cc3`.
  The release code matches a bundle fixture made from the baseline plist.
  The release Services definition, URL schemes, document formats, scripting definition, and type declarations also match the baseline.

The checks also use native resource lookup and plist parsing for all six localization resources.
None overrides the build identity. A temporary bundle with a stale localized name fails the native identity check.
`NSURL` preserves the command, Unicode title, and encoded UUID query for both aliases of each flavor.

Run the evidence from the repository root:

```sh
python3 Tests/DevelopmentBuildReview/round1/torvalds/run.py
```

The final run passed 24 bundle checks, 12 baseline comparisons, and one negative control.
`output.log` contains the full successful output. The native assertions are in `probe.m`.
Each subprocess has a timeout of 45 seconds or less.

The first probe assumed that command-line language arguments force a loaded bundle to select that language.
That assumption failed for the unbundled probe. The final probe uses explicit native localization selection and resource lookup.
It checks normal `NSBundle` identity lookup separately. It does not prove each full application UI under each language.

These checks read built metadata. They do not register Launch Services handlers, run either application, or access notes or keychain items.
They make no preferences changes. They do not exercise Finder routing, Services delivery, GUI behavior, or macOS versions before 26.5.2.
The signature evidence concerns the legacy creator code, not a cryptographic code signature.

The localized-name removals provide the necessary metadata fallback without a second naming mechanism.
The release signature remains byte-compatible despite its non-ASCII plist text.
The source diff and native results provide no reason for an additional abstraction in these boundaries.
