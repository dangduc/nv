#!/usr/bin/env python3
"""Exercise the production tag consumer on explicit 1x and 2x row surfaces."""
from pathlib import Path
import argparse
import os
import subprocess

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
OUTPUT = ROOT / "build/NotesListAppearanceReview/round2/torvalds"


def method(source, signature):
    start = source.index(signature)
    return source[start:source.index("\n}\n", start) + 3]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--negative-controls", action="store_true")
    args = parser.parse_args()
    OUTPUT.mkdir(parents=True, exist_ok=True)
    labels = (ROOT / "Sources/Browser/LabelsListController.m").read_text()
    note = (ROOT / "Sources/Model/NoteObject.m").read_text()
    label_code = "\n".join(method(labels, signature) for signature in (
        "- (NSImage*)cachedLabelImageForWord:", "- (void)invalidateCachedLabelImages", "- (void)dealloc"))
    note_code = "\n".join(method(note, signature) for signature in (
        "- (NSSize)sizeOfLabelBlocks", "- (void)drawLabelBlocksInRect:",
        "- (void)_drawLabelBlocksInRect:"))
    label_include, note_include = OUTPUT / "labels.inc", OUTPUT / "note.inc"
    label_include.write_text(label_code)
    command = ["xcrun", "clang", "-arch", "arm64", "-fno-objc-arc", "-fblocks", "-Werror",
               "-Wno-deprecated-declarations", "-include", "Carbon/Carbon.h",
               "-I", str(OUTPUT), "-I", str(ROOT / "Sources/Utilities"), str(HERE / "probe.m"),
               str(ROOT / "Sources/Utilities/NSBezierPath_NV.m"), "-framework", "Cocoa",
               "-framework", "Carbon", "-o", str(OUTPUT / "probe")]

    def run(name, text, failure=None, zombie=False):
        note_include.write_text(text)
        subprocess.run(command, cwd=ROOT, check=True, timeout=60)
        env = dict(os.environ)
        if zombie:
            env["NSZombieEnabled"] = "YES"
        result = subprocess.run([str(OUTPUT / "probe")], cwd=ROOT, env=env,
                                text=True, capture_output=True, timeout=45)
        log = result.stdout + result.stderr
        (OUTPUT / f"{name}.log").write_text(log)
        if failure:
            assert result.returncode != 0 and failure in log, (name, result.returncode, log)
            print(f"PASS: {name} rejected: {failure}")
        else:
            assert result.returncode == 0, log
            print(log.strip())

    run("production", note_code)
    run("production-zombies", note_code, zombie=True)
    if args.negative_controls:
        try:
            assert "operation:NSCompositeSourceOver fraction:" in note_code
            run("consumer-copy", note_code.replace("operation:NSCompositeSourceOver fraction:",
                "operation:NSCompositeCopy fraction:"), "tag drawing preserves the opaque row")
            assert "nextBoxPoint.x -= [img size].width + 4.0;" in note_code
            run("wrong-right-gap", note_code.replace("nextBoxPoint.x -= [img size].width + 4.0;",
                "nextBoxPoint.x -= [img size].width + 7.0;"), "left and right alignment preserve the same tag pixels")
        finally:
            note_include.write_text(note_code)
            subprocess.run(command, cwd=ROOT, check=True, timeout=60)


if __name__ == "__main__":
    main()
