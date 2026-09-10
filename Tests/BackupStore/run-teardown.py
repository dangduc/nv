#!/usr/bin/env python3
"""Count calls in production teardown methods without opening AppKit windows."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def section(path, start, end):
    source = (ROOT / path).read_text()
    return source[source.index(start):source.index(end, source.index(start))]


session = section("Sources/Editor/NVNoteEditingSession.m", "- (void)close {", "- (void)dealloc {")
editor = section("Sources/Browser/AppController.m", "- (void)_setCurrentNote:", "- (NoteObject*)selectedNoteObject {")
attachment = section("Sources/Browser/AppController_MultipleWindows.m", "- (void)attachLibrary:", "    [self discardViewer];")
# The prefix includes the real deselection ordering. The remaining attachment
# code replaces browser sources and preferences after the old editor detaches.
attachment += "}\n"

template = (Path(__file__).with_name("teardown.m.in")).read_text()
source = template.replace("// SESSION_METHODS", session).replace("// EDITOR_METHODS", editor).replace("// ATTACHMENT_METHODS", attachment)
with tempfile.TemporaryDirectory(prefix="nvalt-backup-teardown-") as temporary:
    temporary = Path(temporary).resolve()
    main = temporary / "teardown.m"
    executable = temporary / "teardown"
    main.write_text(source)
    command = ["xcrun", "clang", "-fno-objc-arc", "-Werror", "-Wno-unused-variable", "-framework", "Cocoa", str(main), "-o", str(executable)]
    subprocess.run(command, check=True)
    subprocess.run([str(executable)], check=True, timeout=30)

    # Prove the checks distinguish each unsafe path from the intended teardown.
    mutations = {
        "source_analysis_not_closed": source.replace("[sourceAnalysis close];", "", 1),
        "session_commit": source.replace("- (void)closeWithoutCommitting {", "- (void)closeWithoutCommitting { [self commitPendingTextChanges];", 1),
        "editor_commit": source.replace("if (finishOldEditing) [self finishEditing];", "[self finishEditing];", 1),
        "deselection_before_detach": source.replace(
            "    [self _setCurrentNote:nil finishingEditing:finishOldLibrary];\n    [notesTableView abortEditing];\n    [notesTableView deselectAll:self];",
            "    [notesTableView abortEditing];\n    [notesTableView deselectAll:self];\n    [self _setCurrentNote:nil finishingEditing:finishOldLibrary];", 1),
    }
    for name, changed in mutations.items():
        if changed == source:
            raise SystemExit(f"mutation no longer applies: {name}")
        main.write_text(changed)
        subprocess.run(command, check=True)
        result = subprocess.run([str(executable)], capture_output=True, text=True, timeout=30)
        if result.returncode == 0:
            raise SystemExit(f"unsafe mutation was accepted: {name}")
        print(f"PASS: rejects {name}: {result.stderr.strip()}")
