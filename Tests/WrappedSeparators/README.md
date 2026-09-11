# Wrapped separator checks

The source editor keeps an isolated ordinary space elastic between non-whitespace characters.
At the right margin, that space can collapse without adding a gap before the next word.
Repeated spaces, trailing spaces, indentation, tabs, and nonbreaking spaces retain their existing behavior.
The stored source is unchanged.

The runner extracts the production glyph delegate and links the production source typesetter.
It reuses the native text-system helpers from the word-wrapping suite.
Each text system has disposable storage and a separate layout manager.

Run these commands from an active macOS desktop session:

```sh
python3 -B Tests/WrappedSeparators/run.py
python3 -B Tests/WrappedSeparators/run.py --negative-control
```

The default includes arm64 and x86_64 on Apple Silicon.
The Intel probe targets macOS 10.13 and runs through Rosetta on Apple Silicon.
Use `--arch x86_64` to run only the shipping architecture.

- `separators`: 684 font, width, and source combinations without leading single-space separator gaps.
- `transitions`: shared layouts, single-to-double spaces, trailing-to-separator spaces, attributed boundaries, batched edits, and resizing.
- `preservation`: repeated spaces, paragraph indentation, tabs, nonbreaking spaces, and Unicode line separators.

The negative control disables the new elasticity exception.
The same wrap-gap assertion must reject that former fixed-width behavior.
Positive and negative binaries use separate output directories under `build/WrappedSeparators/`.

The native editing suite in `Tests/WordWrapping/run.py` covers repeated Space events, Backspace, and composition.
The copied-app suite covers the actual source editor, shared Undo, and note model.
Results on a newer macOS release do not establish behavior on macOS 13.7.8.
