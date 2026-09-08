# Round 2: user-data and compatibility skeptic

PR #4; reviewed storage baseline `f037c7b`. The copied app includes viewer-only changes through `accd9a5`.
This review accepts the removal of rich-text support. It excludes pending conversion deletion, WAL failure, and retry histories covered by Kingsbury.

## Confirmed finding

**[P2] Consume the UTF-8 BOM only once when decoding source**

Location: `Sources/Model/NoteObject.m:100`.

The decoder manually removes the BOM, then passes the remaining bytes to `NSString`'s UTF-8 decoder. That decoder also consumes a leading UTF-8 BOM. A file with a transport BOM followed by a literal source U+FEFF therefore loses the source character during import.

The executable fixture contains a UTF-8 BOM followed by `U+FEFF + "literal\r\n"`. The expected source has 10 UTF-16 units. The imported source has 9. Unchanged export retains the original bytes, which hides the decoding error. After appending `edit`, export has 16 bytes instead of 19:

```text
expected: efbbbf efbbbf 6c69746572616c0d0a65646974
actual:   efbbbf        6c69746572616c0d0a65646974
```

The previous decoder preserves the source U+FEFF for this odd-byte fixture. Giving the complete UTF-8 data to `NSString` also preserves it: Foundation consumes the transport BOM exactly once. Apply only one BOM removal to UTF-8 input and retain a regression check for the edited bytes. Equivalent UTF-16 and UTF-32 fixtures pass.

## Evidence

```sh
python3 Tests/SourceViewerReview/round2/contrarian_data/run.py
```

Final run: exit 0, 53 checks. `output.log` contains the full observations, including one literal-mark loss and zero archive byte failures. The runner injects the probe into a copied app with a unique preferences domain and disposable notes. It uses `build/pr-review/gui.lock`.

The probe calls the production importer, source decoder, note archive methods, and source serializer. Two controls distinguish the UTF-8 finding: the previous decoder and single-pass Foundation decoding. The finding is recorded as observed output; the runner's successful exit means the full review matrix completed.

## Rejected concerns and limits

- Seven tagged encodings preserve source characters and mixed CRLF, CR, and LF sequences: CP-1252, MacRoman, UTF-8, UTF-16 LE/BE, and UTF-32 LE/BE.
- Those encodings retain exact bytes after keyed archive restore and a representable edit. Local syntax metadata restores through the archived preferences and original note UUID.
- High-bit UTF-16/32 encoding identifiers become sign-extended during `decodeInt32ForKey:`. This existed before the redesign. Foundation still emits the expected bytes in all four fixtures. This review does not claim data loss from that observation.
- BOM-only UTF-8/16/32 notes remain empty. UTF-16/32 preserve a literal U+FEFF after their transport BOM.
- An explicit CP-1252 hint takes precedence over the MacRoman fallback. ASCII-only source retains its explicit legacy encoding hint.
- The first test draft used a lightweight preferences delegate for an edit and raised a missing-selector exception. The final probe attaches the complete disposable library for edits. This was a harness error.
- An attempted Core Foundation control also consumed the leading UTF-8 marker; the final control uses complete data with a single Foundation decode.
- The run used macOS 26.5.2 under Rosetta. It does not establish macOS 10.13 behavior or behavior for every legacy encoding. No live sync or external editor was used.
