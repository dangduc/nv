#!/usr/bin/env python3
"""Check exclusive restore rollback and reject a mutation that recovers a foreign WAL."""
from pathlib import Path
import argparse
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--check-baseline-mutation", action="store_true",
                    help="also reject and reproduce the original rollback recovery bug in memory")
arguments = parser.parse_args()

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
    subprocess.run([str(executable), str(temporary), "regression"], check=True, timeout=30)
    if not arguments.check_baseline_mutation:
        raise SystemExit(0)

    # Reproduce the reviewed baseline in memory and show the regression rejects
    # it. No production source is modified by the runner.
    baseline = compiled.replace("if (openingRestoredLibrary || backupRestorePrepared) {", "if (openingRestoredLibrary) {", 1)
    if baseline == compiled:
        raise SystemExit("negative baseline mutation no longer applies")
    main.write_text(baseline)
    subprocess.run(command, check=True, timeout=30)
    result = subprocess.run([str(executable), str(temporary), "regression"], capture_output=True, text=True, timeout=30)
    if result.returncode == 0:
        raise SystemExit("regression accepted rollback journal recovery")
    print(f"PASS: rejects baseline mutation: {result.stderr.strip()}")
    subprocess.run([str(executable), str(temporary), "baseline"], check=True, timeout=30)
