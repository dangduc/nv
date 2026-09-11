# Round 1: platform, compatibility, and CI

Reviewed production commit `2dbfd46` against `bd74bf3` for PR 29.
No actionable findings arose from these three hypotheses.
The review changed no production files.

The evidence ran on macOS 26.5.2 (25F84), with Xcode 26.6 (17F113).
All three hypotheses passed.
`results.json` contains the effective configuration and observed results.

## Hypothesis 1: archive actions select the wrong identity

The runner queried Xcode for the effective build and archive configuration of both schemes.
All four combinations selected the expected product name, executable name, bundle identifier, flavor, and deployment target.
The archive actions preserved the release and Development identities.
The scheme XML also selected the expected configuration for every test, launch, profile, analyze, and archive action.
All buildable references matched the expected app names, including the Development name with a space.

These queries used `-showBuildSettings` with the documented unsigned Intel overrides.
They did not compile or create an Xcode archive.
The archive output locations were temporary paths, distinct from `/Applications` itself.

## Hypothesis 2: the pipeline hides a failure in the first build

The runner extracted the exact build script from `.github/workflows/macos.yml`.
A temporary `xcodebuild` fixture returned exit code 71 for each scheme in turn.
The shell retained code 71 through the loop and `tee` pipeline in both cases.
A release failure stopped the loop before the Development build.
The successful control ran both schemes and returned zero.

The fixture exercised shell control flow only.
It did not represent a compiler, dependency resolver, or GitHub runner.

## Hypothesis 3: CI packages an incompatible or incorrect app

The runner executed the exact packaging script against the existing release product in a temporary checkout.
The real `lipo`, `ditto`, and archive checker all passed.
The extracted ZIP contained one app root: `nvALT.app`.
Its identifier was `net.elasticthreads.nv`, and its runtime flavor was `release`.
The complete extracted Info.plist matched the original release product.

The release executable and both minimum-version plist fields specified macOS 10.13.
The bundle version, short version, and scripting definition matched the baseline source plist.
A negative control changed only the runtime flavor to Development.
The release identity gate rejected that mismatch.

This evidence supports package identity and metadata continuity.
It does not establish preference migration, keychain access, signing continuity, or execution on older macOS versions.
The review did not run either app, register Launch Services handlers, or read user notes, preferences, or keychain items.
The existing full build products supplied the executable evidence.
The review did not repeat those builds or measure the CI timeout margin.

## Reproduction

Run from the repository root:

```sh
python3 Tests/DevelopmentBuildReview/round1/platform/run.py
```

The runner requires both built products in `build/DerivedData/Build/Products`.
It deletes its temporary checkouts, ZIP, extracted app, fixtures, and configuration output directories after the run.
An initial runner attempt encountered Xcode warnings before the JSON output.
The final runner separates the JSON document from those warnings and passed all checks.
