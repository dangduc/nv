# Typing performance reviews

PR #24 uses six independent review perspectives in each of three rounds.
The named perspectives draw on published engineering priorities; the people named did not author these reviews.
Each reviewer writes and runs a probe, records its limits, and reports confirmed defects separately from observations.

Each round has these directories:

- `ousterhout`: ownership and design complexity.
- `luu`: measured performance and practical costs.
- `torvalds`: implementation correctness and resource lifetime.
- `kingsbury`: ordering, consistency, and adversarial scheduling.
- `contrarian_async`: challenges to concurrency and work scheduling.
- `contrarian_ux`: user behavior and compatibility.

Run each directory's `run.py` from the repository root. Read its `findings.md` for prerequisites and results.
Review probes are focused evidence, not substitutes for the application regression suites.
Findings refer to the stated reviewed commit; later rounds can resolve earlier findings.
