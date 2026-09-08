#!/usr/bin/env python3
"""Show how the prior workflow fixture switches to Source while making B."""
import os
from pathlib import Path
import runpy
import tempfile

repo = Path(__file__).resolve().parents[4]
body = (repo / "Tests/Regression/source-workflow/probe-body.m").read_text()
old = '''            NoteObject *intermediate = MakeNote(library, @"Intermediate capture note", @"# Intermediate B");
            [a revealNote:intermediate options:0]; [a revealNote:note options:0];'''
new = '''            NSLog(@"DIAG before MakeNote viewing=%d loading=%d", [a isViewingNote], [preview loading]);
            NoteObject *intermediate = MakeNote(library, @"Intermediate capture note", @"# Intermediate B");
            NSLog(@"DIAG after MakeNote viewing=%d loading=%d", [a isViewingNote], [preview loading]);
            [a revealNote:intermediate options:0]; [a revealNote:note options:0];
            NSLog(@"DIAG after A viewing=%d loading=%d", [a isViewingNote], [preview loading]);'''
assert old in body, "The reviewed workflow fixture changed; inspect it before rerunning this diagnostic."
with tempfile.TemporaryDirectory(prefix="nvalt-workflow-diagnosis-") as directory:
    path = Path(directory) / "diagnostic.m"
    path.write_text(body.replace(old, new))
    os.environ["NV_REVIEW_BODY_PATH"] = str(path)
    runpy.run_path(str(Path(__file__).with_name("run.py")), run_name="__main__")
