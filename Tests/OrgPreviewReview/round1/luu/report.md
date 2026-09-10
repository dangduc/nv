# Org preview review, round 1: Dan Luu perspective

This review uses a Dan Luu-inspired focus on measured costs. It does not represent his review or endorsement.
The reviewed commit is `4467e7a7251ff3846c6d255db3bd64f465fda6b2`, against `f3a8abb2b7942d06ec33af64b4946cfd1b6db163`.

No actionable performance finding emerged from these checks.
The helper and sanitizer run through the existing operation queue.
Main-thread work remains small for the ordinary notebooks in this probe.
Large inputs still have measurable copy, conversion, and memory costs.

## New executable evidence

The generated journals contain headings, TODO states, properties, Unicode prose, emphasis, nested lists, tables, links, source blocks, and quotations.
Section titles and identifiers vary. A final sentinel checks that conversion retains the end of each note.
These are representative synthetic notebooks, not a sample of user notes.

`run.py` checks that the converter in the built app matches the checked-in executable.
The SHA-256 is `34d4469bb611c062a0730040ed1224228262e13d249b5437316947f433fe4359`.
The renderer probe compiles the unchanged production renderer and snapshot classes.

Each size has three helper trials and three renderer trials:

| Input bytes | Helper median | Helper maximum RSS | Renderer callback median | Renderer maximum RSS |
|---:|---:|---:|---:|---:|
| 7,963 | 12.688 ms | 3,670,016 bytes | 51.921 ms | 5,300,224 bytes |
| 95,303 | 22.074 ms | 5,967,872 bytes | 70.543 ms | 9,625,600 bytes |
| 1,019,271 | 128.201 ms | 36,413,440 bytes | 285.965 ms | 59,252,736 bytes |

Helper time includes process launch and pipe transfer through `/usr/bin/time`.
Renderer time includes snapshot construction, queue submission, helper work, sanitization, and main-thread callback delivery.
It excludes WebKit loading, browser layout, drawing, and the application debounce.
The largest rendered document contains 1,562,427 UTF-8 bytes.

RSS values are process high-water measurements on macOS. The helper and renderer peaks are separate and can occur at different times.
The renderer process includes Foundation, source snapshots, IPC buffers, and the sanitizer DOM.
Its three trials share one process. These values do not establish retained-memory growth or a memory ceiling for a 16 MiB note.

## Main-thread work and cancellation

For ordinary notes, snapshot construction takes at most 0.493 ms and queue submission takes at most 0.186 ms.
A 5 ms main-run-loop timer continues during conversion.
Its largest observed interval is 13.986 ms in these trials.
This checks Foundation loop responsiveness, not complete application responsiveness.

The cancellation probe observes a live `nv-org-preview` child before it cancels the active operation.
Cancellation produces one error callback after 0.324 ms.
The operation finishes and the observed child disappears within 34.149 ms after cancellation.
No rendered result or duplicate callback follows.

The 50 ms converter deadline returns the timeout error after 84.195 ms on the largest ordinary journal.
That deadline is not an exact callback-time guarantee. Startup, polling, and process cleanup add elapsed time.
The default deadline remains 15 seconds.

An ordinary input of 16,777,217 bytes receives the source-limit error.
Snapshot construction itself takes 15.816 ms before the worker rejects that input.
This copy cost comes from the existing shared snapshot path.

## Results and limits

All nine helper conversions preserve the expected heading counts, task counts, Unicode, table, escaped code, and final sentinel.
The production renderer passes 75 focused checks, including cancellation and input/deadline errors.
The checks use only ordinary supported content. They do not exercise malformed converter inputs or code execution.

Run the probes from the preview worktree:

```sh
python3 Tests/OrgPreviewReview/round1/luu/run.py
```

The host runs macOS 26.5.2 and Xcode 26.6.
Both binaries run as Intel code through Rosetta.
The renderer targets macOS 10.13, but these checks do not run on that OS version.
The full timings, source hashes, and host details appear in the output files and `metadata.json`.
Other build and review activity can affect elapsed times.
The forced 50 ms timeout check records behavior on this host and is not a portable speed benchmark.
