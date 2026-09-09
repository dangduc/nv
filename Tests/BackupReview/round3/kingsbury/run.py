#!/usr/bin/env python3
"""Check restore preparation with production checkpoint and journal I/O methods.

The archive and model are fixtures. Explicit faults affect only the extracted
production methods. No Intel application or personal notes are opened.
"""
import argparse
from pathlib import Path
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--negative-controls", action="store_true", help="also reject two explicit unsafe mutations")
args = parser.parse_args()
storage = (ROOT / "Sources/Storage/NotationController.m").read_text()
journal = (ROOT / "Sources/Storage/WALController.m").read_text()


def extract(source, start, end):
    begin = source.index(start)
    return source[begin:source.index(end, begin)]


pieces = {
    "CHECKPOINT_SYNC": extract(storage, "static BOOL NVSynchronizeBackupCheckpoint(", "@implementation NotationController"),
    "PREPARE": extract(storage, "- (BOOL)prepareForBackupRestoreWithError:", "- (void)finishPreparedBackupRestore"),
    "JOURNAL_SYNC": extract(journal, "- (BOOL)synchronize {", "- (void)dealloc {"),
    "JOURNAL_DESTROY": extract(journal, "- (BOOL)destroyLogFilePreservingWriterOnFailure {", "- (BOOL)destroyLogFile {"),
}
source = (HERE / "prepare-preservation.m.in").read_text()
for name, body in pieces.items():
    marker = "// PRODUCTION_" + name
    if source.count(marker) != 1:
        raise SystemExit(f"extraction marker changed: {marker}")
    source = source.replace(marker, body)


def compile_probe(directory, content):
    main = directory / "probe.m"
    binary = directory / "probe"
    main.write_text(content)
    subprocess.run(["xcrun", "clang", "-fno-objc-arc", "-Wall", "-Wextra", "-Werror",
                    "-Wno-unused-parameter", "-Wno-deprecated-declarations", "-Wno-sign-compare",
                    "-framework", "Cocoa", str(main), "-o", str(binary)], check=True, timeout=30)
    return binary


def run_probe(binary, directory, scenario):
    return subprocess.run([str(binary), str(directory), scenario], capture_output=True, text=True, timeout=15)


with tempfile.TemporaryDirectory(prefix="nvalt-r3-prepare-") as directory:
    temp = Path(directory)
    binary = compile_probe(temp, source)
    scenarios = ["success", "short-reads", "checkpoint-byte", "checkpoint-size", "checkpoint-missing",
                 "checkpoint-symlink", "directory-symlink", "checkpoint-read", "checkpoint-sync",
                 "directory-sync", "journal-sync", "journal-unlink", "abrupt"]
    for scenario in scenarios:
        data = temp / scenario
        result = run_probe(binary, data, scenario)
        print(result.stdout, end="")
        print(result.stderr, end="")
        if scenario == "abrupt":
            if result.returncode != 73:
                raise SystemExit(f"abrupt fixture returned {result.returncode}, expected 73")
            expected = bytes((index * 73 + 19) % 256 for index in range(131103))
            if (data / "Notes & Settings").read_bytes() != expected or (data / "Interim Note-Changes").exists():
                raise SystemExit("the abrupt process did not preserve its complete checkpoint after journal removal")
            print("PASS: the parent reads all 131103 checkpoint bytes after exit without save or deallocation")
        else:
            result.check_returncode()
    if args.negative_controls:
        mutations = {
            "skip-checkpoint-sync": (
                "if (!NVSynchronizeBackupCheckpoint([snapshot objectForKey:@\"data\"], [self notesDirectoryURL])) {",
                "if (!NVSynchronizeBackupCheckpoint([snapshot objectForKey:@\"data\"], [self notesDirectoryURL]) && NO) {",
                "checkpoint-byte", "an unsynchronized or unusable checkpoint or journal refuses preparation"),
            "close-before-unlink": (
                "if (unlink(currentPath) < 0) return NO;\n    close(logFD);",
                "close(logFD);\n    if (unlink(currentPath) < 0) return NO;",
                "journal-unlink", "failed preparation preserves the original live journal descriptor"),
        }
        for name, (before, after, scenario, expected) in mutations.items():
            if source.count(before) != 1:
                raise SystemExit(f"negative-control mutation no longer applies: {name}")
            binary = compile_probe(temp, source.replace(before, after, 1))
            result = run_probe(binary, temp / name, scenario)
            if result.returncode == 0 or expected not in result.stderr:
                raise SystemExit(f"negative control did not fail as expected: {name}: {result.stdout}{result.stderr}")
            print(f"PASS: rejects explicit negative control {name}: {expected}")
