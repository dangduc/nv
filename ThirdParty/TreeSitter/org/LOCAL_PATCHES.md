# Local Org scanner patch

Base revision: `f15da8e8fcb3a2d764c7092ae6ba4dc87d3b3093` from `nvim-orgmode/tree-sitter-org`.
Only `src/scanner.c` differs from the copied upstream source files.
The generated parser, headers, and MIT license remain unchanged.

The scanner uses a versioned serialization format within Tree-sitter's existing buffer capacity.
Its eight-byte header stores a version, math flag, and three unsigned 16-bit counts.
The payload stores each indentation, bullet, and heading value in two bytes, with explicit little-endian encoding.
The base stack entries are implicit. This state stays in memory and is not part of saved notes.

The encoder checks all counts, value domains, and the complete required size before it writes a normal payload.
Unsupported state produces a one-byte invalid marker.
The decoder checks the entire header, exact payload length, counts, and values before it changes any stack.
Invalid state leaves prior stack values intact and marks the scanner unusable for the current parse.
Indentation and heading counters reject values that their signed 16-bit representation cannot hold.
Stack removal cannot remove the base entries.

A thread-local failure flag remains set through later scanner restoration in the same parse.
`NVSourceParser` resets this flag immediately before its synchronous Org parse and reads it immediately afterward.
On failure, the adapter discards the tree and parser state and selects the existing plain-source fallback.
Other editing-session workers have independent flags. The generic runtime is unchanged.

`Tests/OrgSource/Scanner` checks this patched implementation directly.
The checks include fixed-width round trips, capacity accounting, complete decoding, failure persistence, worker isolation, and adapter recovery.
They do not compile or run an unpatched scanner.
