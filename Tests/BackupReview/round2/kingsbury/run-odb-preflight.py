#!/usr/bin/env python3
"""Check that restore preparation preserves active external-editor sessions."""
from pathlib import Path
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
storage = (ROOT / "Sources/Storage/NotationController.m").read_text()
editor = (ROOT / "ThirdParty/ODBEditor/ODBEditor.m").read_text()
note = (ROOT / "Sources/Model/NoteObject.m").read_text()


def extract(source, start, end):
    begin = source.index(start)
    return source[begin:source.index(end, begin)]


pieces = {
    "CONSTANTS": extract(editor, "NSString * const ODBEditorCustomPathKey", "@interface ODBEditor(Private)"),
    "QUERY": extract(editor, "- (BOOL)hasEditingSessionsForClient:", "- (void)abortAllEditingSessionsForClient:"),
    "EVENTS": extract(editor, "- (void)handleModifiedFileEvent:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)replyEvent {", "\n@end"),
    "NOTE_EVENTS": extract(note, "-(void)odbEditor:(ODBEditor *)editor didModifyFile:", "- (NSRange)nextRangeForWords:"),
    "CHECKPOINT_SYNC": extract(storage, "static BOOL NVSynchronizeBackupCheckpoint(", "@implementation NotationController"),
    "PREPARE": extract(storage, "- (BOOL)prepareForBackupRestoreWithError:", "- (void)finishPreparedBackupRestore"),
}
source = (HERE / "odb-preflight.m.in").read_text()
for name, body in pieces.items():
    source = source.replace("// PRODUCTION_" + name, body)
with tempfile.TemporaryDirectory(prefix="nvalt-r2-odb-") as directory:
    temp = Path(directory)
    main = temp / "probe.m"
    binary = temp / "probe"
    main.write_text(source)
    command = ["xcrun", "clang", "-fno-objc-arc", "-Wall", "-Wextra", "-Werror",
               "-Wno-unused-parameter", "-Wno-deprecated-declarations", "-Wno-sign-compare",
               "-I", str(ROOT / "ThirdParty/ODBEditor"), "-framework", "Cocoa",
               "-framework", "Carbon", str(main), "-o", str(binary)]
    subprocess.run(command, check=True, timeout=30)
    control = temp / "control"
    control.mkdir()
    subprocess.run([str(binary), str(control)], check=True, timeout=30)
    mutation = source.replace("if ([[ODBEditor sharedODBEditor] hasEditingSessionsForClient:note]) {",
                              "if ([[ODBEditor sharedODBEditor] hasEditingSessionsForClient:note] && NO) {", 1)
    if mutation == source:
        raise SystemExit("external-editor guard mutation no longer applies")
    main.write_text(mutation)
    subprocess.run(command, check=True, timeout=30)
    negative = temp / "negative"
    negative.mkdir()
    result = subprocess.run([str(binary), str(negative)], capture_output=True, text=True, timeout=30)
    if result.returncode == 0 or "active external editor prevents preparation" not in result.stderr:
        raise SystemExit(f"guard mutation did not fail as expected: {result.stderr}")
    print("PASS: removing the external-editor guard fails the preparation assertion")
