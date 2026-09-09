#!/usr/bin/env python3
"""Bounded native checks for recovery retry costs and command guard behavior."""
from pathlib import Path
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
storage = (ROOT / "Sources/Storage/NotationController.m").read_text()
application = (ROOT / "Sources/Application/NVApplicationController.m").read_text()


def extract(source, start, end):
    begin = source.index(start)
    return source[begin:source.index(end, begin)]


pieces = {
    "CHECKPOINT_SYNC": extract(storage, "static BOOL NVSynchronizeBackupCheckpoint(", "@implementation NotationController"),
    "INITIALIZATION": extract(storage, "- (BOOL)initializeJournaling {", "//stick the newest unique recovered notes"),
    "FLUSH": extract(storage, "- (BOOL)flushAllNoteChanges {", "- (NSDictionary*)backupSnapshotWithError:"),
    "CAPTURE": extract(storage, "- (NSDictionary*)backupSnapshotWithError:", "- (BOOL)prepareForBackupRestoreWithError:"),
    "PREPARE": extract(storage, "- (BOOL)prepareForBackupRestoreWithError:", "- (void)finishPreparedBackupRestore"),
    "RESUME": extract(storage, "- (BOOL)resumeAfterBackupRestoreFailureWithError:", "- (void)handleJournalError"),
    "AUTOSAVE": extract(storage, "- (void)synchronizeNoteChanges:", "- (NSData*)aliasDataForNoteDirectory"),
    "SCHEDULE": extract(storage, "- (void)scheduleWriteForNote:", "//the gatekeepers!"),
    "RESTORE": extract(application, "- (BOOL)restoreBackupArchive:", "- (IBAction)newWindow:"),
    "EVENTS": "\n".join([
        extract(application, "- (void)application:(NSApplication *)sender openFiles:", "- (void)refreshNotesList"),
        extract(application, "- (BOOL)rejectInvocationDuringBackupRestore:(NSInvocation *)invocation {", "\n@end"),
        extract(application, "- (void)performLibraryInvocation:", "- (void)preserveExternalContents:"),
        extract(application, "- (void)applicationWillTerminate:", "- (IBAction)toggleNVActivation:"),
    ]),
}

# Reuse only the documented fixture collaborators. Replace its scenario in full.
source = (HERE.parents[1] / "round2/kingsbury/rollback-state.m.in").read_text()
source = source[:source.index("static NVApplicationController *activeApp;")]
source = source.replace("static NSUInteger checks, recoveryReads", "static NSUInteger journalOpens, archiveWrites;\nstatic NSUInteger checks, recoveryReads", 1)
source = source.replace("fd = open([file fileSystemRepresentation]", "journalOpens++;\n        fd = open([file fileSystemRepresentation]", 1)
source = source.replace("return [data writeToURL:[directory URLByAppendingPathComponent:@\"fixture-restore-archive\"]", "archiveWrites++;\n    return [data writeToURL:[directory URLByAppendingPathComponent:@\"fixture-restore-archive\"]", 1)
for name, body in pieces.items():
    marker = "// PRODUCTION_" + name
    if source.count(marker) != 1:
        raise SystemExit(f"fixture extraction marker changed: {marker}")
    source = source.replace(marker, body)
source += (HERE / "retry-cost.inc").read_text()


def compile_probe(directory, content):
    main = directory / "probe.m"
    binary = directory / "probe"
    main.write_text(content)
    subprocess.run(["xcrun", "clang", "-DEXPECT_FIXED", "-O2", "-fno-objc-arc", "-Wall", "-Wextra", "-Werror",
                    "-Wno-unused-parameter", "-Wno-deprecated-declarations", "-Wno-sign-compare",
                    "-framework", "Cocoa", "-framework", "Carbon", str(main), "-o", str(binary)],
                   check=True, timeout=45)
    return binary


with tempfile.TemporaryDirectory(prefix="nvalt-r3-retry-cost-") as directory:
    temp = Path(directory)
    binary = compile_probe(temp, source)
    control = temp / "control"
    control.mkdir()
    result = subprocess.run([str(binary), str(control)], text=True, capture_output=True, timeout=30)
    print(result.stdout, end="")
    print(result.stderr, end="")
    result.check_returncode()

    # A test-only mutation must fail before its second recovery response.
    before = "if (!backupRestoreInProgress) return NO;\n    NSUInteger length"
    after = "if (YES) return NO;\n    NSUInteger length"
    if source.count(before) != 1:
        raise SystemExit("command guard mutation no longer applies")
    binary = compile_probe(temp, source.replace(before, after, 1))
    negative = temp / "negative"
    negative.mkdir()
    result = subprocess.run([str(binary), str(negative)], text=True, capture_output=True, timeout=30)
    if result.returncode == 0 or "paused guard handles each return shape" not in result.stderr:
        raise SystemExit(f"guard mutation did not fail as expected: {result.stdout}{result.stderr}")
    print("PASS: removing the recovery command guard fails the first paused return-shape assertion")
