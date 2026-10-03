# CI checks

The [macOS workflow](../../.github/workflows/macos.yml) builds both app configurations with Xcode 16.4 in two independent jobs:

| Job | Runner | Binary architecture | Minimum macOS |
| --- | --- | --- | --- |
| Intel | `macos-15-intel` | `x86_64` | 10.13 |
| Apple Silicon | `macos-15` | `arm64` | 11.0 |

These are [standard GitHub-hosted runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).
The [Apple Silicon runner image](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-arm64-Readme.md) includes Xcode 16.4 and the pinned Rust toolchain.
It builds `Notation Release` (`ForBuilding`), then `Notation Develop` (`Development`).
CI disables code signing. It does not require repository secrets.
Before the app build, CI compiles and executes the [native search suites](../FuzzySearch/README.md) for each job's architecture on its matching hardware.
These checks cover native order, the search service, duplicate rows, persistence, and shared-source invalidation.
This is native test execution, not just cross-compilation. It does not run the full desktop integration suites.
The cached preference-callback dispatch also executes on each architecture, checking the Objective-C method arguments and sender exclusion.

## Apple Silicon dependencies

The checked-in OpenSSL archive and preview executables remain Intel artifacts for existing local builds.
The Apple Silicon job runs [build-arm64-dependencies.py](../../.github/scripts/build-arm64-dependencies.py) before Xcode.
It downloads the exact existing OpenSSL 1.0.2d and MultiMarkdown 4.7.1 source revisions, plus MultiMarkdown's pinned greg parser generator.
[arm64-dependencies.json](../../.github/arm64-dependencies.json) records immutable source URLs and SHA-256 checksums, verified before extraction.
OpenSSL uses its portable 64-bit C target without assembly; this is an architecture rebuild, not a crypto library upgrade.
The Org helper uses the existing vendored sources and Rust 1.98.1 with `--locked --offline`, targeting `aarch64-apple-darwin`.
Only the disposable job checkout receives the rebuilt library, generated OpenSSL headers and native helpers.

The job verifies each dependency with `lipo`, runs MD5 and AES-256-CBC/PKCS7 checks against fixed/system references,
and compares six native Markdown/Org outputs byte-for-byte with the checked Intel reference fixtures.
The Org rebuild also verifies deployment target, system-only linkage, stripped symbols and native conversion.
Dependency logs and a manifest of downloaded sources and generated binary hashes accompany the build log.
The separate Xcode 26.0.1 icon compiler and committed icon resources are unchanged.

The workflow runs for pull requests to `master`, pushes to `master` or `*-release`, and manual runs.
The `*-release` pattern matches top-level branches such as `2026.09-release`. It does not match `codex/example-release` or `example-release-candidate`.
The build job has read access to the repository.
Separate tag and release jobs have write access after a successful build and artifact upload.

## Artifacts

Each successful job uploads `Neo-Notational-V-macos-<architecture>-<run number>-<attempt>.zip` for 30 days (`x86_64` or `arm64`).
The archive contains the stable `Neo Notational V.app` from `ForBuilding`.
CI also builds and checks `Neo Notational V Development.app` as a separate product.
The build log remains available for seven days, including failed builds.
The ZIP file preserves app permissions.

Before packaging, CI checks each app's name, executable, bundle identifier, build flavor, and creator signature.
It also checks URL registrations, document handler ranks, service names and shortcuts, and localized application names.
Development must use its own identity and URL schemes. Its document handler rank is `None`, and its service has no default shortcut.
The build also checks the compiled icon catalog's source hashes and both apps' icon keys and resource bytes.
The separate [App icon compatibility workflow](../../.github/workflows/app-icons.yml) checks system icon selection on macOS 15 and 26.
See [AppIcons/README.md](../AppIcons/README.md) for the native checks and local commands.

The archive check reads the ZIP file and checks these properties.
Its tests reject archives with lost executable permissions for the app, MultiMarkdown or Org helper.
Both jobs pass `--arch` to inspect all three executable payloads' Mach-O headers inside the ZIP.
An arm64 app with an Intel preview helper fails; runner labels and archive filenames do not establish binary architecture.
The archive must also contain four highlighting queries and `ThirdPartyNotices.txt` under `Contents/Resources/Syntax/`.
It must contain the three search dependency notices under `Contents/Resources/SearchLicenses/`.
These resources must be nonempty regular files. The checks reject missing, empty, or whitespace-only resources, directories, and symbolic links.

## Automatic tags

Successful pushes and manual runs on `master` create `build-<run number>` at `GITHUB_SHA`.
This SHA identifies the commit that CI built. Pull requests and other branches cannot create tags.
Tag creation occurs after both build jobs succeed.

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

The existing automatic release contains the unsigned Intel `Neo Notational V.app` ZIP from the Intel build job.
The Apple Silicon ZIP is available as a workflow artifact. Both build jobs must pass before publication.
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
  'build/DerivedData/Build/Products/ForBuilding/Neo Notational V.app' build/Neo-Notational-V-ci-check.zip
python3 .github/scripts/check-app-archive.py build/Neo-Notational-V-ci-check.zip
```

After building both schemes, check their application identities:

```sh
python3 .github/scripts/check-app-identity.py \
  'build/DerivedData/Build/Products/ForBuilding/Neo Notational V.app' release
python3 .github/scripts/check-app-identity.py \
  'build/DerivedData/Build/Products/Development/Neo Notational V Development.app' development
```

The [desktop integration suites](../README.md) require a separate run in an active desktop session.
The current local URL-rendering check fails on macOS 13.7.8. CI build success does not establish that all desktop checks pass.
