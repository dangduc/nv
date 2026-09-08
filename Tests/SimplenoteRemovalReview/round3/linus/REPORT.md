# Round 3: final app artifact and retained dependencies

This review uses a Linus Torvalds-inspired integration perspective. It does not represent his participation or endorsement.

**Finding: no actionable defect introduced by this PR.** The packaged app retains the resources and executable code needed by its local features.
None of the seven remaining vendored dependencies becomes removable as a whole through Simplenote removal.
This is not a claim that every individual file in each vendored directory is necessary.

Reviewed head: `f9cc501628b1c4e61b7e655e205f0c36ca00260f`.
The final tracked production and build tree matches `f38a8cb`; later commits change review evidence and the legacy fixture.
The executable SHA-256 is `d61aea6619f6c4322efac164d7409ac131aa0ce2a8760d874850c34443331ede`.

## Original executable evidence

[artifact.py](artifact.py) packages the existing Development app with the CI `ditto` command.
It runs the CI archive checker, then independently inspects the ZIP and extracted app.
It also compiles [dependencies.c](dependencies.c) against the eight parser objects and two Crypto objects from the app's actual linker input list.
That executable links the retained OpenSSL archive and reads highlighting queries from the extracted app.

The final run passed **52 artifact assertions and 35 native dependency assertions**.
See [artifact.log](artifact.log) and [native.log](native.log).

| Boundary | Evidence and local purpose |
| --- | --- |
| MultiMarkdown | The packaged helper matches its tracked bytes and executes heading/bold conversion. The renderer invokes it for Markdown at [NVMarkupRenderer.m](../../../../Sources/Preview/NVMarkupRenderer.m#L236). |
| Textile 2.12 | Both packaged files match tracked bytes. The extracted Perl helper and module execute heading/bold conversion. The renderer invokes them for Textile at [NVMarkupRenderer.m](../../../../Sources/Preview/NVMarkupRenderer.m#L237). |
| Tree-sitter | The app's highlighter object references the runtime and all four grammar entry points. These definitions exist in the shipped executable. The retained parser objects accept and compile all four shipped queries, parse synthetic source without errors, and produce captures. |
| Crypto | The data utility object references vendored PBKDF2, SHA-1, and the legacy MD5 functions. PBKDF2 references vendored HMAC-SHA1. Local password import still references vendored IDEA. The PBKDF2 implementation produces the expected fixed-vector bytes. |
| OpenSSL | The data utility object references AES encryption/decryption functions; their definitions are present in the app. The archive passes an AES fixed-vector encryption and decryption check. This library also supports local journal and database encryption. |
| ODBEditor | The final library controller object references the vendor class, and the shipped app defines it. Local database settings still reinitialize external editing at [NotationController.m](../../../../Sources/Storage/NotationController.m#L606). |
| PTHotKeys | The final preferences object references the hotkey, hotkey center, and key-combination classes. The app defines all three. Its packaged key-name mapping remains readable and matches the tracked mapping. [GlobalPrefs.m](../../../../Sources/Preferences/GlobalPrefs.m#L354) uses these classes for application activation. |

The parser experiment produced 6 JSON captures, 8 HTML captures, 3 Markdown block captures, and 8 Markdown inline captures.
These are bounded examples that establish working runtime, grammar, and resource connections.
They do not measure highlighting completeness or performance.

The artifact checks also establish these properties:

- All **287 app files** survive ZIP packaging with identical bytes and permission bits.
- All **102 final linker object inputs** exist, with no retired service objects.
- The extracted executable is Intel `x86_64` and matches the reviewed binary hash.
- Its **15 direct dynamic dependencies** use system paths. Removed direct IOKit and SystemConfiguration dependencies are absent.
- The app contains no embedded vendor frameworks or removed sync classes. Archive filenames exclude the retired service/configuration/framework names checked by the probe.
- All four packaged highlighting queries match their pinned manifest hashes. The packaged syntax notices match their tracked bytes.
- The tracked project no longer contains the sync implementation, API-key example, or service configuration reference. The ignored personal configuration file is never read.

## Negative controls

The script mutates only an extracted disposable app copy:

1. Removing `Textile_2.12/Text/Textile.pm` causes the real Perl conversion command to fail while loading the module. See [missing-textile.log](missing-textile.log).
2. Removing the shipped JSON query causes the native query experiment to fail before parsing. See [missing-query.log](missing-query.log).
3. Removing MultiMarkdown's execute bits causes process launch to fail with `PermissionError`.

These controls establish that the successful operations depend on retained bundle contents and permissions.
No source, user note, account, or personal configuration is mutated.

## Reproduction and limits

From the repository root after the Development build:

```sh
python3 Tests/SimplenoteRemovalReview/round3/linus/artifact.py \
  > Tests/SimplenoteRemovalReview/round3/linus/artifact.log 2>&1
```

Environment: macOS 26.5.2, Xcode 26.6 (17F113), Intel Development app under Rosetta, deployment target 10.13.
The script uses temporary build directories and removes its ZIP, extracted bundle, and native executable on completion.

The first probe drafts used a nonexistent `MultiMarkdown/bin` path and a plist parser that cannot read the legacy OpenStep key-name file.
The corrected probe uses the actual tracked helper path and `plutil` for that file. Neither issue was an application defect.

The native dependency executable reuses built objects; it does not invoke the app's editor or storage methods.
The fixed crypto vectors check linkage and basic execution, not cryptographic security or archive compatibility.
ODB and hotkey evidence proves concrete linked consumers and packaged data; this round does not register a system hotkey or launch an external editor.
The system dependency check examines direct load commands, not transitive dependencies or availability on older macOS releases.
Earlier rounds cover actual preference nib initialization and local external-editor callbacks.
This round reuses the validated build because the production tree is unchanged; it does not perform another clean Xcode build.
