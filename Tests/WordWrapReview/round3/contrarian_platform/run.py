#!/usr/bin/env python3
"""Check native Unicode edits at wrapping boundaries against frozen production."""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import subprocess

here = Path(__file__).resolve().parent
repo = here.parents[3]
reviewed = "63911bf2c66d438f178b43a8b9e996787e29acc9"
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--arch", action="append", choices=["arm64", "x86_64"])
args = parser.parse_args()
out = repo / "build/WordWrapReview/round3/contrarian_platform"
out.mkdir(parents=True, exist_ok=True)
hashes = {}
for path in ["Sources/Editor/NVSourceTypesetter.m", "Sources/Editor/NVSourceTypesetter.h", "Sources/Editor/LinkingEditor.m"]:
    content = (repo / path).read_bytes()
    assert content == subprocess.check_output(["git", "show", f"{reviewed}:{path}"], cwd=repo), path
    hashes[path] = hashlib.sha256(content).hexdigest()
source = (repo / "Sources/Editor/LinkingEditor.m").read_text()
start = source.index("- (NSUInteger)layoutManager:")
opening = source.index("{", start)
assert "shouldGenerateGlyphs:" in source[start:opening]
end, depth = opening + 1, 1
while depth:
    depth += (source[end] == "{") - (source[end] == "}")
    end += 1
(out / "space-delegate.h").write_text("@interface SpaceDelegate:NSObject<NSLayoutManagerDelegate>\n@end\n@implementation SpaceDelegate\n" + source[start:end] + "\n@end\n")
summary = {"reviewedCommit": reviewed, "productionHashes": hashes,
           "macOS": subprocess.check_output(["sw_vers"], text=True),
           "xcode": subprocess.check_output(["xcodebuild", "-version"], text=True), "architectures": {}}
for arch in args.arch or (["arm64", "x86_64"] if platform.machine() == "arm64" else ["x86_64"]):
    binary = out / f"probe-{arch}"
    subprocess.run(["xcrun", "clang", "-arch", arch,
                    f"-mmacosx-version-min={'11.0' if arch == 'arm64' else '10.13'}",
                    "-fno-objc-arc", "-Wno-deprecated-declarations", "-Wall", "-Wextra", "-Wno-unused-parameter",
                    "-framework", "Cocoa", "-framework", "CoreText", "-I", str(out),
                    "-I", str(repo / "Sources/Editor"), str(here / "probe.m"),
                    str(repo / "Sources/Editor/NVSourceTypesetter.m"), "-o", str(binary)], check=True)
    result = out / f"results-{arch}.json"
    run = subprocess.run(["arch", f"-{arch}", str(binary), str(result)], capture_output=True, text=True, timeout=45)
    (out / f"output-{arch}.log").write_text(run.stdout + run.stderr)
    print(run.stdout + run.stderr, end="", flush=True)
    run.check_returncode()
    observations = json.loads(result.read_text())
    observations.pop("records")
    observations["detailedResults"] = str(result.relative_to(repo))
    summary["architectures"][arch] = observations
summary["probeHashes"] = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in [here / "run.py", here / "probe.m"]}
(here / "results.json").write_text(json.dumps(summary, indent=2) + "\n")
