#!/usr/bin/env python3
"""Exercise production journal initialization/rollback with a competing WAL fixture."""
from pathlib import Path
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
source = (ROOT / "Sources/Storage/NotationController.m").read_text()


def method(start, end):
    begin = source.index(start)
    return source[begin:source.index(end, begin)]


initialization = method("- (BOOL)initializeJournaling {", "//stick the newest unique recovered notes")
resume = method("- (BOOL)resumeAfterBackupRestoreFailureWithError:", "- (void)handleJournalError {")
template = (HERE / "probe.m.in").read_text()
compiled = template.replace("// INITIALIZATION", initialization).replace("// RESUME", resume)
with tempfile.TemporaryDirectory(prefix="nvalt-review-rollback-") as directory:
    temporary = Path(directory)
    main = temporary / "probe.m"
    executable = temporary / "probe"
    main.write_text(compiled)
    command = ["xcrun", "clang", "-fno-objc-arc", "-Wall", "-Wextra", "-Werror",
               "-Wno-unused-parameter", "-framework", "Foundation", str(main), "-o", str(executable)]
    subprocess.run(command, check=True, timeout=30)
    subprocess.run([str(executable), str(temporary), "baseline"], check=True, timeout=30)

    # An in-memory candidate guard demonstrates that exclusive rollback can keep
    # the competing file intact. It does not edit the shipping implementation.
    guarded = compiled.replace("if (openingRestoredLibrary) {", "if (openingRestoredLibrary || backupRestorePrepared) {", 1)
    if guarded == compiled:
        raise SystemExit("candidate guard no longer applies")
    main.write_text(guarded)
    subprocess.run(command, check=True, timeout=30)
    subprocess.run([str(executable), str(temporary), "guarded"], check=True, timeout=30)
