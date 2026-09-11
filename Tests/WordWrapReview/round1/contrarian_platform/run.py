#!/usr/bin/env python3
"""Run bounded, windowless comparisons against the frozen production typesetter."""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import subprocess

here = Path(__file__).resolve().parent
repo = here.parents[3]
reviewed = "4b049709b2cecc6eac80514586ccacc119d12802"
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--arch", action="append", choices=["arm64", "x86_64"])
parser.add_argument("--negative-control", action="store_true")
args = parser.parse_args()
out = repo / "build/WordWrapReview/round1/contrarian_platform"
out.mkdir(parents=True, exist_ok=True)
hashes = {}
for relative in ["Sources/Editor/NVSourceTypesetter.m", "Sources/Editor/NVSourceTypesetter.h", "Sources/Editor/LinkingEditor.m"]:
    actual = (repo / relative).read_bytes()
    frozen = subprocess.check_output(["git", "show", f"{reviewed}:{relative}"], cwd=repo)
    assert actual == frozen, f"Production source differs from reviewed commit: {relative}"
    hashes[relative] = hashlib.sha256(actual).hexdigest()
source = (repo / "Sources/Editor/LinkingEditor.m").read_text()
start = source.index("- (NSUInteger)layoutManager:")
opening = source.index("{", start)
assert "shouldGenerateGlyphs:" in source[start:opening]
end, depth = opening + 1, 1
while depth:
    depth += (source[end] == "{") - (source[end] == "}")
    end += 1
(out / "space-delegate.h").write_text(
    "@interface SpaceDelegate:NSObject<NSLayoutManagerDelegate>\n@end\n"
    "@implementation SpaceDelegate\n" + source[start:end] + "\n@end\n")
metadata = {"reviewedCommit": reviewed, "hashes": hashes,
            "macOS": subprocess.check_output(["sw_vers"], text=True),
            "xcode": subprocess.check_output(["xcodebuild", "-version"], text=True)}
(out / "metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")
for arch in args.arch or (["arm64", "x86_64"] if platform.machine() == "arm64" else ["x86_64"]):
    binary = out / f"probe-{arch}"
    subprocess.run(["xcrun", "clang", "-arch", arch,
                    f"-mmacosx-version-min={'11.0' if arch == 'arm64' else '10.13'}",
                    "-fno-objc-arc", "-Wno-deprecated-declarations", "-Wall", "-Wextra",
                    "-Wno-unused-parameter", "-framework", "Cocoa", "-framework", "CoreText",
                    "-I", str(out), "-I", str(repo / "Sources/Editor"), str(here / "probe.m"),
                    str(repo / "Sources/Editor/NVSourceTypesetter.m"), "-o", str(binary)], check=True)
    for suite in (["words"] if args.negative_control else ["unicode", "words", "invalidation"]):
        label = f"{suite}-{arch}" + ("-negative" if args.negative_control else "")
        result = out / f"{label}.json"
        command = ["arch", f"-{arch}", str(binary), suite, str(result)]
        if args.negative_control:
            command.append("negative")
        run = subprocess.run(command,
                             timeout=45, capture_output=True, text=True)
        (out / f"{label}.log").write_text(run.stdout + run.stderr)
        print(run.stdout + run.stderr, end="", flush=True)
        run.check_returncode()
        print(result, flush=True)
