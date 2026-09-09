#!/usr/bin/env python3
"""Measure native cell/tag drawing and count production cache work per redraw."""
from pathlib import Path
import argparse
import json
import subprocess

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
OUTPUT = ROOT / "build/NotesListAppearanceReview/round2/luu"
BASE = "878961a"


def method(source, signature):
    start = source.index(signature)
    return source[start:source.index("\n}\n", start) + 3]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--negative-controls", action="store_true")
    args = parser.parse_args()
    OUTPUT.mkdir(parents=True, exist_ok=True)
    path = "Sources/Browser/LabelsListController.m"
    current = method((ROOT / path).read_text(), "- (NSImage*)cachedLabelImageForWord:")
    base = subprocess.check_output(["git", "show", f"{BASE}:{path}"], cwd=ROOT, text=True)
    (OUTPUT / "current.inc").write_text(current)
    (OUTPUT / "base.inc").write_text(method(base, "- (NSImage*)cachedLabelImageForWord:"))
    note = (ROOT / "Sources/Model/NoteObject.m").read_text()
    (OUTPUT / "note.inc").write_text("\n".join(method(note, selector) for selector in (
        "- (NSArray*)orderedLabelTitles", "- (void)drawLabelBlocksInRect:",
        "- (void)_drawLabelBlocksInRect:")))
    string = (ROOT / "Sources/Utilities/NSString_NV.m").read_text()
    (OUTPUT / "words.inc").write_text(method(string, "- (NSArray*)labelCompatibleWords"))
    (OUTPUT / "separators.inc").write_text(method(string, "+ (NSCharacterSet*)labelSeparatorCharacterSet"))
    binary = OUTPUT / "probe"
    command = ["xcrun", "clang", "-x", "objective-c", "-arch", "arm64", "-O2",
               "-fno-objc-arc", "-fblocks", "-Wno-deprecated-declarations",
               "-Wno-incomplete-implementation", "-include", "Cocoa/Cocoa.h",
               "-include", "Carbon/Carbon.h", "-Dforce_inline=__inline__", "-DIsLeopardOrLater=1",
               "-DCOMPILE_ASSERT(X,N)=_Static_assert(X,#N)"]
    for directory in sorted((ROOT / "Sources").iterdir()):
        if directory.is_dir():
            command += ["-I", str(directory)]
    command += ["-I", str(OUTPUT), str(HERE / "probe.m"),
                "Sources/Utilities/NSString_CustomTruncation.m",
                "Sources/Utilities/NSBezierPath_NV.m", "Sources/Utilities/BufferUtils.c",
                "-framework", "Cocoa", "-framework", "Carbon", "-o", str(binary)]

    def compile_probe():
        result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, timeout=60)
        (OUTPUT / "compile.log").write_text(result.stdout + result.stderr)
        result.check_returncode()

    compile_probe()
    result = subprocess.run([str(binary)], cwd=ROOT, text=True, capture_output=True, timeout=120)
    (OUTPUT / "output.log").write_text(result.stdout + result.stderr)
    print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="")
    result.check_returncode()
    report = json.loads(result.stdout.splitlines()[-1])
    (OUTPUT / "measurements.json").write_text(json.dumps(report, indent=2) + "\n")
    if args.negative_controls:
        old = "NSImage *img = [labelImages objectForKey:imgKey];"
        assert current.count(old) == 1
        try:
            (OUTPUT / "current.inc").write_text(current.replace(old, "NSImage *img = nil;"))
            compile_probe()
            rejected = subprocess.run([str(binary)], cwd=ROOT, text=True, capture_output=True, timeout=30)
            log = rejected.stdout + rejected.stderr
            (OUTPUT / "bypass-cache.log").write_text(log)
            assert rejected.returncode != 0 and "warm redraw does not replace cached images" in log, log
            print("PASS: bypass-cache mutation fails the actual-draw image reuse assertion")
        finally:
            (OUTPUT / "current.inc").write_text(current)
            compile_probe()


if __name__ == "__main__":
    main()
