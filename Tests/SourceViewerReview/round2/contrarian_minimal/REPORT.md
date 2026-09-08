# Round 2: complexity deletion advocate

Reviewed PR #4 at `f037c7b781fa2a3c58d7b00cb440ba3e7239b615`, using its clean Development app.
This contrarian perspective tests the costs of retained mechanisms and verifies removal of obsolete resources.

No new actionable finding was demonstrated.

## Resource closure

`audit-closure.py` exited 0. Its output is in `assets-output.log`.
The round-one CM1 resources are absent from the source tree, Xcode project, and built application.
The check also covers removed preview interfaces, templates, TaskPaper conversion, and the old Markdown processor.
In total, it checks ten removed resource names.

The retained MultiMarkdown binary, Textile directory, and Syntax directory each have exactly one resource-copy entry.
Their eight files match the shipped files byte for byte. Directory comparisons reject extra or missing files.
Both bundled markup helpers produce the expected heading and strong text when launched from `/private/tmp`.
This exercises the Textile module lookup independently of the repository working directory.

## Allocation and restoration

`run.py` exited 0 with **26 checks**. Its output is in `runtime-output.log`.
The new Objective-C instrumentation counts actual provider initialization, view loading, and close calls.
It runs inside a copied application with disposable notes, a separate defaults domain, and the shared GUI lock.

- Startup, note selection, four Source or unsupported restoration states, and 800 menu validations construct no provider or web view.
- Opening a second Source window and restoring its selected note also construct no provider.
- A supported Preview restoration constructs exactly one provider and one web view. The original Source window remains without a provider.
- HTML Preview restoration preserves the note's JSON syntax metadata.
- Ten subsequent Source restorations close the prior provider and construct no replacement.
- Direct Preview commands with no selected note leave the provider absent.

These results reject the concern that source-only restoration or routine menu validation pays the cost of transient viewer construction.

## Commands and limits

```sh
python3 Tests/SourceViewerReview/round2/contrarian_minimal/audit-closure.py
python3 Tests/SourceViewerReview/round2/contrarian_minimal/run.py
```

The probes ran on macOS 26.5.2 with the unsigned Intel Development application under Rosetta.
The allocation probe counts explicit provider and view construction. It does not measure framework loading, WebKit process memory, or final object deallocation.
The resource check covers the named removed assets and retained rendering/highlighting resources; it does not classify every image in the application.
The concurrent viewer capture-ordering fix is outside this review's scope.
