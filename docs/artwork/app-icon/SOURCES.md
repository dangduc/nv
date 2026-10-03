# Icon artwork sources

## Flowing Fanfold

The user selected the combined Flowing Fanfold paper and architectural-isometric
Saturn V launchpad composition (`R2-P2.png`). Its exact selected bytes are
preserved as `fanfold/selected-composition.png`; the content hash is recorded
in `fanfold/provenance.json`.

Three reference-preserving edits were made with the built-in imagegen tool:

- `full.png`: detailed composition with the full rocket and platform.
- `compact.png`: wider rocket, larger structural elements and simple print marks.
- `micro.png`: broad silhouettes, reduced tower bays and blank paper.

`fanfold/generation-prompts.json` records the adaptation briefs, and
`fanfold/provenance.json` records source identity and content hashes. No external
photographs or newly downloaded third-party artwork were introduced in this
adaptation. Generated paper printing is decorative texture; it is not a verified
Apollo source-code transcription.

## Previous artwork

The old NASA-derived Saturn V SVG, custom red tower drawing, supplied Apollo 11
code excerpt, paper drawings and their original attribution records are retained
in `revisions/03-peach-flat-launchpad/`. Earlier saved revisions are unchanged.
Those SVG components are not used by the Flowing Fanfold build pipeline.
