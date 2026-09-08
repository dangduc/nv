# Tree-sitter source analysis

This directory contains the C runtime and generated parsers for JSON, HTML, and Markdown.
Markdown uses separate block and inline parsers.
The application does not require a parser generator, Node.js, Rust, or an external syntax process.

[manifest.json](manifest.json) records upstream repositories, revisions, file sizes, and SHA-256 hashes.
The runtime accepts language ABI versions 13 through 15.
The JSON and HTML grammars use ABI 14. Both Markdown grammars use ABI 15.

The application compiles [wrapper units](../../Sources/Editor/TreeSitter) with unique names to prevent Xcode object-file collisions.
Each wrapper includes one unmodified upstream source file.
The wrappers compile `runtime/src/lib.c` and each grammar's `src/parser.c`.
HTML and both Markdown grammars also compile `src/scanner.c`.
The runtime includes the other C files through `lib.c`. Those files are not separate compilation units.

Only the native runtime is enabled.
`wasm_store.c` supplies native stubs that `lib.c` requires.
The WASM standard library, language bindings, generators, grammar descriptions, and package build files are excluded.

The highlighting queries reside in [Resources/Syntax](../../Resources/Syntax).
These pinned queries contain no predicates or directives.
The adapter rejects a query that contains either construct, because the C query API does not evaluate them.
Language injections are not enabled. Textile uses plain source display.

Each component retains its MIT license. The runtime also retains the Unicode license notices.
[ThirdPartyNotices.txt](../../Resources/Syntax/ThirdPartyNotices.txt) contains these notices for distribution with the application.
