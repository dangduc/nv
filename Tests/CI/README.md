# CI checks

The [macOS workflow](../../.github/workflows/macos.yml) builds both Intel app configurations with Xcode 16.4 on `macos-15-intel`.
It builds `Notation Release` (`ForBuilding`), then `Notation Develop` (`Development`).
CI disables code signing. It does not require repository secrets.
Before the app build, CI runs the [native search suites](../FuzzySearch/README.md) on Intel.
These checks cover native order, the search service, duplicate rows, persistence, and shared-source invalidation.

The workflow runs for pull requests to `master`, pushes to `master` or `*-release`, and manual runs.
The `*-release` pattern matches top-level branches such as `2026.09-release`. It does not match `codex/example-release` or `example-release-candidate`.
The build job has read access to the repository.
Separate tag and release jobs have write access after a successful build and artifact upload.

## Artifacts

Each successful build uploads `nvALT-macos-x86_64-<run number>-<attempt>.zip` for 30 days.
The archive contains the stable `nvALT.app` from `ForBuilding`.
CI also builds and checks `nvALT Development.app` as a separate product.
The build log remains available for seven days, including failed builds.
The ZIP file preserves app permissions.

Before packaging, CI checks each app's name, executable, bundle identifier, build flavor, and creator signature.
It also checks URL registrations, document handler ranks, service names and shortcuts, and localized application names.
Development must use its own identity and URL schemes. Its document handler rank is `None`, and its service has no default shortcut.

The archive check reads the ZIP file and checks these properties.
Its tests reject archives with lost executable permissions for the app or MultiMarkdown.
The archive must also contain four highlighting queries and `ThirdPartyNotices.txt` under `Contents/Resources/Syntax/`.
It must contain the three search dependency notices under `Contents/Resources/SearchLicenses/`.
These resources must be nonempty regular files. The checks reject missing, empty, or whitespace-only resources, directories, and symbolic links.

## Automatic tags

Successful pushes and manual runs on `master` create `build-<run number>` at `GITHUB_SHA`.
This SHA identifies the commit that CI built. Pull requests and other branches cannot create tags.
Tag creation occurs after the complete build job succeeds.

If a tag points directly to the same commit, a rerun reuses it.
A conflicting tag causes a failure. The script never moves an existing tag.
API errors cause failures. If a concurrent retry finds the expected tag, it succeeds.

Build tags do not change `CFBundleVersion` or `CFBundleShortVersionString`.
Tag creation does not create a GitHub Release or start another build.
No personal access token is necessary.

## Automatic releases

Successful pushes and manual runs on `*-release` branches publish a GitHub Release in the current repository.
In `dangduc/nv`, releases appear on the [Releases page](https://github.com/dangduc/nv/releases).
Forks publish in their own repository. Pull requests, tags, branch deletions, and other branches cannot publish releases.

Each release uses `release-<run number>-<attempt>` as its tag.
The tag points directly to `GITHUB_SHA`, which identifies the source commit for the app.
A conflicting tag stops publication. Existing tags never move.
Each workflow rerun uses a new attempt number and release tag.
These tags do not change the application version fields.

The release contains the unsigned Intel `nvALT.app` ZIP from the build job.
The download step selects its artifact ID and preserves the ZIP without extraction.
The release job repeats the archive check, uploads the ZIP into a draft, then publishes the release.
A failed upload leaves an unpublished draft. A workflow rerun creates a new release instead of replacing an existing download.
If only the release job needs a rerun, it uses the artifact from the successful build job.

The release title identifies the branch and build attempt. The description records the commit and links to the workflow run.
It also states that the app is unsigned, lacks notarization, and requires Rosetta on Apple Silicon.
Automatic releases do not replace the repository's explicit `Latest` selection.
They use the built-in `GITHUB_TOKEN` and require no additional secrets.
Branch protection remains a separate repository configuration.

## Run the checks locally

Run the tests from the repository root:

```sh
python3 -B -m unittest discover -s Tests/CI -v
```

The tag and release tests use a simulated API or CLI. They do not create remote tags or releases.

After a local build, create an app archive:

```sh
ditto -c -k --sequesterRsrc --keepParent \
  build/DerivedData/Build/Products/ForBuilding/nvALT.app build/nvALT-ci-check.zip
python3 .github/scripts/check-app-archive.py build/nvALT-ci-check.zip
```

After building both schemes, check their application identities:

```sh
python3 .github/scripts/check-app-identity.py \
  build/DerivedData/Build/Products/ForBuilding/nvALT.app release
python3 .github/scripts/check-app-identity.py \
  'build/DerivedData/Build/Products/Development/nvALT Development.app' development
```

The [desktop integration suites](../README.md) require a separate run in an active desktop session.
The current local URL-rendering check fails on macOS 13.7.8. CI build success does not establish that all desktop checks pass.
