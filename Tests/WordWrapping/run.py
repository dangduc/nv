#!/usr/bin/env python3
"""Exercise the production source typesetter in standalone Cocoa text systems."""
import argparse
import fcntl
import json
from pathlib import Path
import platform
import subprocess


def glyph_delegate(source):
    """Copy the live glyph hook, not a second implementation of space layout."""
    start = source.index("- (NSUInteger)layoutManager:")
    assert "shouldGenerateGlyphs:" in source[start:source.index("{", start)]
    opening = source.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--arch", action="append", choices=("arm64", "x86_64"))
parser.add_argument("--suite", choices=("matrix", "geometry", "editing", "performance"), action="append")
parser.add_argument("--negative-control", action="store_true",
                    help="Verify that the previous character wrapping fails the prose check.")
args = parser.parse_args()
repo = Path(__file__).resolve().parents[2]
output = repo / "build/WordWrapping"
output.mkdir(parents=True, exist_ok=True)
implementation = (repo / "Sources/Editor/LinkingEditor.m").read_text()
(output / "space-delegate.h").write_text(
    "@interface SpaceDelegate : NSObject <NSLayoutManagerDelegate>\n@end\n"
    "@implementation SpaceDelegate\n" + glyph_delegate(implementation) + "\n@end\n")
architectures = args.arch or (["arm64", "x86_64"] if platform.machine() == "arm64" else ["x86_64"])
suites = ["matrix"] if args.negative_control else args.suite or ["matrix", "geometry", "editing", "performance"]
common = Path(subprocess.check_output(
    ["git", "rev-parse", "--git-common-dir"], cwd=repo, text=True).strip())
if not common.is_absolute():
    common = (repo / common).resolve()
lock_path = common.parent / "build/pr-review/gui.lock"
lock_path.parent.mkdir(parents=True, exist_ok=True)
for architecture in architectures:
    binary = output / f"probe-{architecture}"
    # Apple Silicon starts at macOS 11. The shipping Intel app targets 10.13.
    minimum = "11.0" if architecture == "arm64" else "10.13"
    subprocess.run([
        "xcrun", "clang", "-arch", architecture, f"-mmacosx-version-min={minimum}",
        "-fno-objc-arc", "-Wno-deprecated-declarations", "-Wall", "-Wextra",
        "-Wno-unused-parameter", "-framework", "Cocoa", "-framework", "CoreText",
        "-I", str(output), "-I", str(repo / "Sources/Editor"),
        str(Path(__file__).with_name("probe.m")),
        str(repo / "Sources/Editor/NVSourceTypesetter.m"), "-o", str(binary),
    ], check=True)
    for suite in suites:
        label = f"{suite}-{architecture}" + ("-negative" if args.negative_control else "")
        result = output / f"{label}.json"
        command = ["arch", f"-{architecture}", str(binary), suite, str(result)]
        if args.negative_control:
            command.append("negative")
        print(f"Running {label} (deployment target {minimum})", flush=True)
        with lock_path.open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            run = subprocess.run(command, timeout=120, capture_output=True, text=True)
        print(run.stdout, end="")
        print(run.stderr, end="")
        if args.negative_control:
            assert run.returncode == 1 and "fitting word stays on one line" in run.stderr, run
            print("PASS: previous character wrapping rejected by the prose assertion")
            continue
        run.check_returncode()
        report = json.loads(result.read_text())
        assert report["checks"] > 0
        print(result)
