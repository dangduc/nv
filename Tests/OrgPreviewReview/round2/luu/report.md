# Org preview review, round 2: Dan Luu perspective

This review uses a Dan Luu-inspired focus on measured costs. It does not represent his review or endorsement.
No new actionable finding emerged from the heading-index change.

The reviewed helper contains 366,408 bytes.
Its SHA-256 is `dc5c563e75589ed615bc9faaad465f093ba180ac9c1b6baa3c4b2d874123fcba`.
The helper in the built app has the same hash.
The production source and renderer hashes appear in `metadata.json`.
The helper was frozen while the root agent prepared the fix commit.

## New workloads and correctness oracle

The probe generates three sizes of each workload:

- Journals vary heading count, with eight internal links per heading.
- Link-heavy notes hold 64 headings and vary references per heading.
- Merged journals contain duplicate titles and IDs, a generated-anchor collision, and Unicode IDs.

These are ordinary Org constructs. No malformed converter input participates.
The duplicate-ID cases check the documented first-heading policy for ambiguous references.

An independent HTML parser collects headings and links from the output.
Each source reference records its intended heading before conversion.
The oracle checks unique heading IDs and matches every decoded fragment to that intended heading.
It also checks a late explicit ID against an earlier generated anchor, Unicode fragment encoding, and the final content sentinel.

All 483,229 oracle assertions pass across helper trials and actual renderer results.
The source fixture hashes remain unchanged.
The old helper serves only as a timing comparison. Its unresolved links are not accepted as a correctness oracle.

## Cost of the fix

The comparison uses the original helper from commit `4467e7a7251ff3846c6d255db3bd64f465fda6b2` and the frozen current helper.
Each binary receives exactly the same input in three trials.
The execution order alternates to reduce consistent cache-order bias.
The elapsed times include process startup, pipes, conversion, and `/usr/bin/time` overhead.

| Workload | Input bytes | Headings | Links | Before median | After median |
|---|---:|---:|---:|---:|---:|
| Journal | 22,551 | 64 | 512 | 13.836 ms | 14.290 ms |
| Journal | 93,287 | 256 | 2,048 | 21.860 ms | 23.467 ms |
| Journal | 379,143 | 1,024 | 8,192 | 56.128 ms | 63.091 ms |
| Links | 34,807 | 64 | 1,024 | 14.929 ms | 15.883 ms |
| Links | 109,111 | 64 | 4,096 | 22.088 ms | 24.767 ms |
| Links | 416,311 | 64 | 16,384 | 52.565 ms | 64.069 ms |
| Duplicate IDs | 14,251 | 32 | 256 | 12.680 ms | 13.162 ms |
| Duplicate IDs | 116,314 | 256 | 2,048 | 22.954 ms | 25.235 ms |
| Duplicate IDs | 468,250 | 1,024 | 8,192 | 58.931 ms | 69.157 ms |

The measured added work grows with document and reference count across these inputs.
The largest increases range from about 7 to 12 ms.
The fix also emits longer output with heading anchors and resolved fragments.
These comparisons measure the complete fix, not only the index construction or hash lookups.

The largest current helper peaks at 21,139,456 RSS bytes across these fixtures.
The corresponding largest original-helper peak is 20,946,944 bytes.
These are process high-water observations, not exact allocations attributable to the new maps.
They do not establish memory bounds at the full 16 MiB input limit.

The first original-helper launch takes 420.198 ms on the smallest journal.
The output records that sample. The median for that case is 13.836 ms.
First-launch behavior and host activity can outweigh conversion cost in a single sample.

## Actual renderer and replacement

The native probe compiles the unchanged production renderer and snapshot classes.
It uses the current converter from the built app.
Three complete renders pass the same independent heading/link oracle:

| Workload | Submission | Callback | Completion and cleanup | Parent peak RSS |
|---|---:|---:|---:|---:|
| Journal, 1,024 headings | 0.203 ms | 312.240 ms | 316.921 ms | 26,210,304 bytes |
| Links, 16,384 references | 0.185 ms | 156.544 ms | 161.060 ms | 28,565,504 bytes |
| Duplicate IDs, 1,024 headings | 0.198 ms | 167.234 ms | 172.227 ms | 28,958,720 bytes |

Each row is one observation, not a median.
The callback times include helper work and HTML sanitization.
The different startup and scheduling costs prevent a direct comparison with helper-only medians.

The replacement case observes an active converter child before cancellation.
It then submits a new snapshot for the same note with a different heading and link.
The old request returns one cancellation callback after 0.376 ms.
The new request succeeds, its fragment points to the new heading, and no old reference labels appear.
The replacement and old-child cleanup finish within 49.380 ms after cancellation.
All 30 native checks pass, including source identity and exactly one callback per request.

## Reproduction and limits

Run the evidence:

```sh
python3 Tests/OrgPreviewReview/round2/luu/run.py
```

`helper-output.json` preserves all 54 helper measurements, including the first-launch outlier.
`renderer-output.txt` records the four renderer cases.
`metadata.json` records helper hashes, source hashes, fixture hashes, and the oracle count.

The host runs macOS 26.5.2 and Xcode 26.6. Both helpers and the native renderer run through Rosetta.
The checks exclude WebKit loading, drawing, application debounce, editor Undo, and actual macOS 10.13 execution.
The small sample count supports these bounded comparisons, not universal latency or memory guarantees.
