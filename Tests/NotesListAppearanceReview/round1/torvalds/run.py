#!/usr/bin/env python3
"""Check production tag-image ownership, color keys, and compositing on native AppKit."""
from pathlib import Path
import argparse
import os
import subprocess

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
OUTPUT = ROOT / "build/NotesListAppearanceReview/round1/torvalds"


def method(source, signature):
    start = source.index(signature)
    return source[start:source.index("\n}\n", start) + 3]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--negative-controls", action="store_true")
    args = parser.parse_args()
    OUTPUT.mkdir(parents=True, exist_ok=True)
    source = (ROOT / "Sources/Browser/LabelsListController.m").read_text()
    original = "\n".join(method(source, signature) for signature in (
        "- (NSImage*)cachedLabelImageForWord:", "- (void)invalidateCachedLabelImages", "- (void)dealloc"))
    include = OUTPUT / "production.inc"
    command = ["xcrun", "clang", "-arch", "arm64", "-fno-objc-arc", "-fblocks",
               "-Werror", "-Wno-deprecated-declarations", "-include", "Carbon/Carbon.h",
               "-I", str(OUTPUT), "-I", str(ROOT / "Sources/Utilities"),
               str(HERE / "probe.m"), str(ROOT / "Sources/Utilities/NSBezierPath_NV.m"),
               "-framework", "Cocoa", "-framework", "Carbon", "-o", str(OUTPUT / "probe")]

    def run(name, text, expected=None, zombie=False):
        include.write_text(text)
        subprocess.run(command, cwd=ROOT, check=True, timeout=60)
        env = dict(os.environ)
        if zombie:
            env["NSZombieEnabled"] = "YES"
        result = subprocess.run([str(OUTPUT / "probe")], cwd=ROOT, env=env,
                                text=True, capture_output=True, timeout=30)
        log = result.stdout + result.stderr
        (OUTPUT / f"{name}.log").write_text(log)
        if expected:
            assert result.returncode != 0 and expected in log, (name, result.returncode, log)
            print(f"PASS: {name} rejected: {expected}")
        else:
            assert result.returncode == 0, log
            print(log.strip())

    run("production", original)
    run("production-zombies", original, zombie=True)
    compatibility = OUTPUT / "compatibility.m"
    compatibility.write_text((HERE / "probe.m").read_text().split("static unsigned checks", 1)[0])
    result = subprocess.run([
        "xcrun", "clang", "-arch", "x86_64", "-mmacosx-version-min=10.13", "-fsyntax-only",
        "-fno-objc-arc", "-fblocks", "-Werror", "-Werror=unguarded-availability",
        "-Werror=unguarded-availability-new", "-Wno-deprecated-declarations",
        "-include", "Carbon/Carbon.h", "-I", str(OUTPUT),
        "-I", str(ROOT / "Sources/Utilities"), str(compatibility)],
        cwd=ROOT, capture_output=True, text=True, timeout=60)
    (OUTPUT / "compatibility.log").write_text(result.stdout + result.stderr)
    assert result.returncode == 0, result.stdout + result.stderr
    print("PASS: extracted production methods compile for x86_64/macOS 10.13 with availability errors enabled")
    if args.negative_controls:
        try:
            key = "@[[aWord lowercaseString], @(isHighlighted), fillColor]"
            assert key in original
            run("omit-color-key", original.replace(key, "@[[aWord lowercaseString], @(isHighlighted)]"),
                "distinct alpha values require distinct cached images")
            operation = "NSCompositingOperationDestinationOut"
            assert operation in original
            run("source-out", original.replace(operation, "NSCompositingOperationSourceOut"),
                "glyph coverage removes the expected translucent fill")
            store = "[labelImages setObject:[img autorelease] forKey:imgKey];"
            assert store in original
            run("leaked-image", original.replace(store, "[labelImages setObject:img forKey:imgKey];"),
                "invalidating the cache releases its images")
        finally:
            include.write_text(original)
            subprocess.run(command, cwd=ROOT, check=True, timeout=60)


if __name__ == "__main__":
    main()
