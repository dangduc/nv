#!/usr/bin/env python3
"""Run extracted restore, rollback, autosave, and checkpoint control flow.

The archive encoder, note model, and UI are fixtures. The journal fixture uses
real exclusive file creation and writes. No shipping app or personal notes open.
"""
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
}
template = (HERE / "rollback-state.m.in").read_text()
for name, source in pieces.items():
    template = template.replace("// PRODUCTION_" + name, source)
with tempfile.TemporaryDirectory(prefix="nvalt-r2-rollback-") as directory:
    temp = Path(directory)
    main = temp / "probe.m"
    binary = temp / "probe"
    main.write_text(template)
    command = ["xcrun", "clang", "-fno-objc-arc", "-Wall", "-Wextra", "-Werror",
               "-Wno-unused-parameter", "-Wno-deprecated-declarations", "-Wno-sign-compare",
               "-framework", "Cocoa", "-framework", "Carbon", str(main), "-o", str(binary)]
    subprocess.run(command, check=True, timeout=30)
    control = temp / "control"
    control.mkdir()
    subprocess.run([str(binary), str(control), "control"], check=True, timeout=30)
    abrupt = temp / "abrupt"
    abrupt.mkdir()
    result = subprocess.run([str(binary), str(abrupt), "abrupt"], check=False, timeout=30)
    if result.returncode != 73:
        raise SystemExit(f"abrupt-exit fixture returned {result.returncode}, expected 73")
    if (abrupt / "original" / "Notes & Settings").read_bytes() != b"before restore":
        raise SystemExit("abrupt-exit checkpoint does not match the expected pre-edit bytes")
    if (abrupt / "Interim Note-Changes").exists():
        raise SystemExit("abrupt-exit fixture unexpectedly retained a recovery journal")
    print("PASS: separate process exited without cleanup; durable checkpoint predates both later edits; no journal remains")
