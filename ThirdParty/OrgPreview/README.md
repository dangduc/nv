# Org preview converter

`nv-org-preview` converts UTF-8 Org source from standard input to HTML on standard output.
The application uses this bundled Intel executable. A normal Xcode build does not require Rust, Emacs, or Pandoc.
The executable targets macOS 10.13 and links only the system library.

The converter uses [Orgize 0.9.0](https://github.com/PoiScript/orgize/tree/71292fea36a0398da132d077f68607c158977c84).
[src/main.rs](src/main.rs) adapts the upstream HTML exporter for nvALT.
It preserves TODO state, priorities, heading tags, checkbox text, relative file links, and escaped example lines.
It emits separate HTML lists when item markers change between ordered and unordered forms.
The parser and the note source remain unchanged.

Links such as `[[*Heading]]` and `[[Heading]]` resolve to headings in the current note, including forward references.
Each heading has a unique anchor. A valid `CUSTOM_ID` takes precedence over `ID`; otherwise, the converter generates an anchor.
Both properties can serve as link aliases through `[[#id]]`.
Unicode headings and IDs are supported. Fragment links encode ID bytes for URL navigation.
Duplicate titles and IDs resolve to the first matching heading in document order.
Later duplicate IDs receive generated anchors. IDs that contain whitespace or control characters also receive generated anchors.
Generated anchors depend on heading order and can change when headings are inserted or removed.
Use unique `CUSTOM_ID` properties for stable links.

Heading matching uses exact title text, including inline markup, without TODO keywords, priorities, or tags.
External URLs and explicit file paths retain their targets. Use `file:` to distinguish a file from an identical heading title.
Unresolved references retain their original link targets.
Dedicated targets, named elements, and links to IDs in other notes are outside this viewer's scope.

Headings, emphasis, lists, tables, links, quotations, source blocks, and example blocks have regression checks.
Checkboxes appear as text and remain read-only.
The converter does not evaluate code, expand includes, or process Emacs configuration.
Include and setup-file directives remain visible as literal text.
Org macros, footnotes, agenda functions, and complete Emacs export settings are outside this viewer's scope.
Explicit list counters, description-list markers, and inline markup inside link descriptions remain literal text.

The converter rejects input that exceeds 16 MiB and output that exceeds 32 MiB.
The application also enforces its conversion deadline, cancellation, and HTML limits.
The existing HTML sanitizer and viewer resource rules apply to Org output and HTML export.

## Dependencies

[Cargo.lock](Cargo.lock) pins the eight source dependencies.
[manifest.json](manifest.json) records their registry checksums, licenses, source hashes, and the executable hash.
The `vendor` directory contains seven unchanged crates.
The `orgize` directory contains Orgize source with one Cargo change: `indextree` uses its `std` feature without its default macros.
This change removes thirteen unused dependencies. Orgize Rust source is unchanged.
`orgize/Cargo.toml.orig` retains the upstream manifest before Cargo normalization.

The application includes [the dependency notices](../../Resources/OrgPreviewNotices.txt).
It also includes [the Rust standard library notices](licenses/Rust-1.98.1-COPYRIGHT-library.html) from the pinned toolchain.
These upstream library notices cover all Rust targets, including dependencies that this Intel helper does not use.

## Rebuild

The rebuild requires full Xcode, Rust 1.98.1, and the `x86_64-apple-darwin` standard library.
Rustup can install this toolchain from [rust-toolchain.toml](rust-toolchain.toml).
The Cargo build uses the vendored sources with `--locked --offline`.

From the repository root, run:

```sh
python3 Scripts/rebuild-org-preview.py --update-manifest
python3 Tests/Regression/org-preview/run.py
python3 Tests/Regression/source-viewers/run.py
```

If Cargo is outside `PATH`, pass its absolute path with `--cargo`.
The script supplies the toolchain library path that direct Cargo invocations require for symbol stripping.
It rejects failed stripping, including warnings that Cargo reports with a successful exit status.
The script checks the compiler version, architecture, deployment target, linked libraries, stripped symbols, and a native conversion.
It remaps repository paths in the executable. The manifest records the compiler and SDK that produced the bundled artifact.
A different SDK can produce different executable bytes.
Two clean builds from the same source directory matched except for the 16-byte Mach-O UUID.
The artifact hash identifies the exact executable that the application ships.

To inspect the checked-in artifact without Rust, run:

```sh
python3 Scripts/rebuild-org-preview.py --verify-only
```

The native checks run on macOS 26.5.2 through Rosetta.
The deployment load command and Rust target support establish the macOS 10.13 build target.
This repository does not contain a test result from an actual macOS 10.13 system.
