# Org source review, round 1: Dan Luu perspective

This review uses a Dan Luu-inspired focus on measured cost and user-visible behavior. It does not represent his review or endorsement.
The reviewed commit is `decc6788e1a746b5425f3cd248cd93071c98b8b2`, against `f3a8abb2b7942d06ec33af64b4946cfd1b6db163`.

## Finding: P2 — repeated line scans block editing of dense Org paragraphs

Location: `Sources/Editor/AttributedPlainText.m:245` in the reviewed commit.

The Org link loop calls `lineRangeForRange:` once for every bracketed link on the same line.
Each call scans the line again. The measured cost grows approximately fourfold each time the link count doubles.
`LinkingEditor.m:1169` calls this method synchronously from `didChangeText`.
The parser deadline cannot limit this work because link decoration runs separately.

The probe repeats `[[https://example.com][label]] ` on one line.
It calls the exact production methods on an `NSMutableAttributedString` for the full note and then a one-character range.
The Org dispatcher expands that second range to the whole line.
Five trials provide these median elapsed times:

| Links | UTF-16 units | Full refresh | One-character refresh | Cached-line experiment, one-character refresh |
|---:|---:|---:|---:|---:|
| 1,000 | 31,000 | 38.512 ms | 39.962 ms | 6.655 ms |
| 2,000 | 62,000 | 143.014 ms | 145.501 ms | 13.477 ms |
| 4,000 | 124,000 | 553.211 ms | 560.726 ms | 30.070 ms |
| 8,000 | 248,000 | 2,166.308 ms | 2,199.296 ms | 72.019 ms |

The experiment changes only the repeated line-boundary lookup in a generated copy of the production methods.
It retains the current line end until the cursor reaches the next line.
Both variants preserve every source character, label range, target URL, and expected link count.
The probe also covers one link per line. An 8,000-link full refresh takes 46.057 ms in production and 45.562 ms in the experiment.

The recommended fix is to calculate each line boundary once and reuse it for all links on that line.
A deterministic work-count regression can protect this behavior without a machine-dependent time limit.

## Highlighter results

The independent parser probe compiles the unchanged production highlighter, runtime, and grammar wrappers.
It covers prose, emphasis, links, and heading/property text at 16,384, 65,536, 262,144, and 524,288 UTF-16 units.
Each combination has three fresh-parser trials and a small-note recovery check.

All 78,405 range, capture-count, and recovery checks pass.
The largest fixtures return the existing fallback result. The observed maximum elapsed time is 142.354 ms across all 48 trials.
The nominal 120 ms parser deadline is not an exact wall-time guarantee.
This probe finds no actionable highlighter defect in these bounded inputs.

The supplemental pass allocates two data buffers totaling three bytes per UTF-16 unit.
The existing 512 Ki-unit input guard bounds these buffers to 1.5 MiB per parse.
This calculation excludes parser trees, captures, source snapshots, and allocator overhead. It is not a whole-process memory measurement.

## Reproduction and limits

Run the link probe:

```sh
python3 Tests/OrgSourceReview/round1/luu/run.py
```

Run the parser probe:

```sh
python3 Tests/OrgSourceReview/round1/luu/run-parser.py
```

The host runs macOS 26.5.2 and Xcode 26.6. Both probes compile Intel code for a macOS 10.13 deployment target and run through Rosetta.
The measurements cover isolated methods. They exclude window layout, drawing, event delivery, and the cost of an actual character mutation.
They establish method cost on this host, not total typing latency or behavior on macOS 10.13.
Concurrent development work can affect absolute times. The same-size experiment and size scaling provide stronger evidence than one elapsed time.

Evidence files:

- `metadata.json` records the original source hash and host.
- `production.txt` and `cached-line-experiment.txt` record all link measurements.
- `parser.txt` records all highlighter measurements and its source hash.
- `link-probe.m` and `parser-probe.m` contain the independent workloads.

The original finding and measurements were recorded before the production fix.

## Resolution

The production loop now retains the current line end until the cursor reaches the next line.
The maintained link suite passes 2,060 checks, including a dense paragraph and an actual one-character insertion.
Its string wrapper counts the source units covered by line-boundary requests. No elapsed-time assertion depends on machine speed.
The same regression rejects the original loop in `decc678` with the expected work-count failure.

The fixed production method has an 8,000-link full-refresh median of 50.280 ms and a one-character-refresh median of 78.632 ms.
The corresponding original medians are 2,166.308 ms and 2,199.296 ms.
All labels, targets, link counts, and source characters still match.
These figures remove the repeated line scans. They do not promise a frame-time limit for every note or eliminate all synchronous decoration cost.

Run the maintained regression:

```sh
python3 Tests/OrgSource/Links/run.py
```

Run the original-loop rejection check:

```sh
python3 Tests/OrgSourceReview/round1/luu/check-regression.py
```

Run the current production measurements:

```sh
python3 Tests/OrgSourceReview/round1/luu/run.py --current
```

`production-fixed.txt` and `metadata-fixed.json` record the final measurements and source hash.
`regression-before.txt` records the expected failure against the original source.
The default measurement command retains access to the original implementation through its commit ID.
