#!/usr/bin/env python3
"""Check appearance ownership through native AppKit and extracted production methods."""
from pathlib import Path
import argparse
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
OUTPUT = ROOT / "build/NotesListAppearanceReview/round1/ousterhout"


def method(path, signature):
    source = (ROOT / path).read_text()
    start = source.index(signature)
    end = source.index("\n}", start) + 2
    return source[start:end] + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--negative-controls", action="store_true")
    args = parser.parse_args()
    OUTPUT.mkdir(parents=True, exist_ok=True)
    sources = {
        "labels.inc": method("Sources/Browser/LabelsListController.m", "- (NSImage*)cachedLabelImageForWord:"),
        "invalidate.inc": method("Sources/Browser/LabelsListController.m", "- (void)invalidateCachedLabelImages"),
        "colors.inc": method("Sources/Browser/AppController.m", "- (void)updateColorScheme{"),
    }
    for name, source in sources.items():
        (OUTPUT / name).write_text(source)
    binary = OUTPUT / "probe"
    command = ["xcrun", "clang", "-x", "objective-c", "-include", "Cocoa/Cocoa.h", "-include", "Carbon/Carbon.h",
               "-Dforce_inline=__inline__", "-DCOMPILE_ASSERT(X,N)=_Static_assert(X,#N)", "-fno-objc-arc",
               "-Wno-incomplete-implementation", "-Wno-deprecated-declarations"]
    for directory in sorted((ROOT / "Sources").iterdir()):
        if directory.is_dir():
            command += ["-I", str(directory)]
    command += ["-I", str(OUTPUT), str(HERE / "probe.m"), "Sources/Utilities/NSString_CustomTruncation.m",
                "Sources/Utilities/NSBezierPath_NV.m", "Sources/Utilities/BufferUtils.c", "-framework", "Cocoa",
                "-framework", "Carbon", "-o", str(binary)]

    def run(name):
        subprocess.run(command, cwd=ROOT, check=True, capture_output=True, text=True)
        result = subprocess.run([str(binary)], cwd=ROOT, capture_output=True, text=True, timeout=30)
        (OUTPUT / f"{name}.log").write_text(result.stdout + result.stderr)
        return result

    result = run("current")
    print(result.stdout, end="")
    if result.returncode:
        raise RuntimeError(result.stderr)
    if args.negative_controls:
        cases = [
            ("labels.inc", ", @(isHighlighted), fillColor]", ", @(isHighlighted)]", "unkeyed-color", "different resolved colors cannot reuse"),
            ("colors.inc", "[notesTableView setBackgroundColor:[NSColor textBackgroundColor]]", "[notesTableView setBackgroundColor:backgrndColor]", "editor-coupling", "list background ignores"),
        ]
        for name, old, new, label, expected in cases:
            assert sources[name].count(old) == 1, old
            try:
                (OUTPUT / name).write_text(sources[name].replace(old, new))
                result = run(label)
                assert result.returncode != 0 and expected in result.stderr, result
                print(f"PASS: {label} mutation rejected")
            finally:
                (OUTPUT / name).write_text(sources[name])
        subprocess.run(command, cwd=ROOT, check=True, capture_output=True, text=True)


if __name__ == "__main__":
    main()
