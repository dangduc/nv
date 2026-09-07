# CI checks

The [macOS workflow](../../.github/workflows/macos.yml) builds an Intel Development app with Xcode 16.4 on `macos-15-intel`.
CI copies the placeholder `SimperiumConfig-example.h` and disables code signing. It does not require repository secrets.

The workflow runs for pull requests to `master`, pushes to `master`, and manual runs.
The build job has read access to the repository. A separate tag job has write access after a successful build and artifact upload.

## Artifacts

Each successful build uploads `nvALT-macos-x86_64-<run number>-<attempt>.zip` for 30 days.
The build log remains available for seven days, including failed builds.
The ZIP file preserves app permissions and framework symlinks.

The archive check reads the ZIP file and checks these properties.
Its tests reject archives with lost executable permissions or flattened framework symlinks.

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

## Run the checks locally

Run the tests from the repository root:

```sh
python3 -B -m unittest discover -s Tests/CI -v
```

The tag tests use a simulated API. They do not create remote tags.

After a local build, create an app archive:

```sh
ditto -c -k --sequesterRsrc --keepParent \
  build/DerivedData/Build/Products/Development/nvALT.app build/nvALT-ci-check.zip
python3 .github/scripts/check-app-archive.py build/nvALT-ci-check.zip
```

The [desktop integration suites](../README.md) require a separate run in an active desktop session.
The current local URL-rendering check fails on macOS 13.7.8. CI build success does not establish that all desktop checks pass.
