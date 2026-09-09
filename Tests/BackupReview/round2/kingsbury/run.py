#!/usr/bin/env python3
"""Run extracted restore, rollback, autosave, and checkpoint control flow.

The archive encoder, note model, and UI are fixtures. The journal fixture uses
real exclusive file creation and writes. No shipping app or personal notes open.
"""
from pathlib import Path
import argparse
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
storage = (ROOT / "Sources/Storage/NotationController.m").read_text()
application = (ROOT / "Sources/Application/NVApplicationController.m").read_text()
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--baseline", action="store_true", help="reproduce the reviewed a89f835 rollback state")
args = parser.parse_args()
if args.baseline:
    application = subprocess.check_output(["git", "show", "a89f8351646f824f51ed6ea80b94f724f37d0303:Sources/Application/NVApplicationController.m"], cwd=ROOT, text=True)


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
if not args.baseline:
    pieces["EVENTS"] = "\n".join([
        extract(application, "- (void)application:(NSApplication *)sender openFiles:", "- (void)refreshNotesList"),
        extract(application, "- (BOOL)rejectInvocationDuringBackupRestore:(NSInvocation *)invocation {", "\n@end"),
        extract(application, "- (void)performLibraryInvocation:", "- (void)preserveExternalContents:"),
        extract(application, "- (void)applicationWillTerminate:", "- (IBAction)toggleNVActivation:"),
    ])
template = (HERE / "rollback-state.m.in").read_text()
for name, source in pieces.items():
    template = template.replace("// PRODUCTION_" + name, source)


def run_probe(binary, directory, mode):
    result = subprocess.run([str(binary), str(directory), mode], check=False, capture_output=True, text=True, timeout=30)
    if "fixture-note-secret" in result.stdout + result.stderr:
        raise SystemExit("recovery logs exposed the exception's fixture note content")
    print(result.stdout, end="")
    print(result.stderr, end="")
    return result
with tempfile.TemporaryDirectory(prefix="nvalt-r2-rollback-") as directory:
    temp = Path(directory)
    main = temp / "probe.m"
    binary = temp / "probe"
    main.write_text(template)
    command = ["xcrun", "clang", "-fno-objc-arc", "-Wall", "-Wextra", "-Werror",
               "-Wno-unused-parameter", "-Wno-deprecated-declarations", "-Wno-sign-compare",
               "-framework", "Cocoa", "-framework", "Carbon", str(main), "-o", str(binary)]
    if not args.baseline:
        command.insert(2, "-DEXPECT_FIXED")
    subprocess.run(command, check=True, timeout=30)
    control = temp / "control"
    control.mkdir()
    run_probe(binary, control, "control").check_returncode()
    abrupt = temp / "abrupt"
    abrupt.mkdir()
    result = run_probe(binary, abrupt, "abrupt")
    if result.returncode != 73:
        raise SystemExit(f"abrupt-exit fixture returned {result.returncode}, expected 73")
    if (abrupt / "original" / "Notes & Settings").read_bytes() != b"before restore":
        raise SystemExit("abrupt-exit checkpoint does not match the expected pre-edit bytes")
    journal = abrupt / "Interim Note-Changes"
    if args.baseline:
        if journal.exists():
            raise SystemExit("abrupt-exit fixture unexpectedly retained a recovery journal")
        print("PASS: baseline process exited without cleanup; durable checkpoint predates both later edits; no journal remains")
    else:
        if journal.read_bytes() != b"edit after recovery":
            raise SystemExit("recovered autosave did not preserve its edit in the journal")
        print("PASS: fixed process exited without cleanup; recovery journal retains the later edit")
        terminating = temp / "terminating"
        terminating.mkdir()
        result = run_probe(binary, terminating, "terminating")
        if result.returncode != 75:
            raise SystemExit(f"termination-state fixture returned {result.returncode}, expected 75")
        initialization = temp / "initialization"
        initialization.mkdir()
        run_probe(binary, initialization, "initialization").check_returncode()
