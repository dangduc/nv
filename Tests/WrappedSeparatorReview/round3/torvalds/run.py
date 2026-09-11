#!/usr/bin/env python3
"""Compare frozen callbacks with independent Foundation cluster observations."""
import hashlib
import json
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
OUT = REPO / "build/WrappedSeparatorReview/round3/torvalds"
OUT.mkdir(parents=True, exist_ok=True)
REFS = {"PreviousDelegate": "2ea92180939a3e51df8fe867ad548140ed455868",
        "CorrectedDelegate": "e022109eaf2bad6583512c2ed2b48561d9dae011"}
hashes = {}
parts = []
for name, ref in REFS.items():
    source = subprocess.check_output(["git", "show", f"{ref}:Sources/Editor/LinkingEditor.m"], cwd=REPO, text=True, timeout=15)
    start = source.index("- (NSUInteger)layoutManager:")
    opening = source.index("{", start)
    assert "shouldGenerateGlyphs:" in source[start:opening]
    end, depth = opening + 1, 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    hook = source[start:end]
    hashes[name] = hashlib.sha256(hook.encode()).hexdigest()
    parts.append(f"@interface {name}:NSObject<NSLayoutManagerDelegate>\n@end\n@implementation {name}\n{hook}\n@end\n")
(OUT / "production.inc").write_text("\n".join(parts))
summary = {"commits": REFS, "callbackSHA256": hashes,
           "macOS": subprocess.check_output(["sw_vers"], text=True),
           "xcode": subprocess.check_output(["xcodebuild", "-version"], text=True), "runs": []}
for arch in ["arm64", "x86_64"]:
    binary = OUT / f"probe-{arch}"
    subprocess.run(["xcrun", "clang", "-arch", arch, f"-mmacosx-version-min={'11.0' if arch == 'arm64' else '10.13'}",
                    "-fno-objc-arc", "-fblocks", "-Wall", "-Wextra", "-Werror", "-framework", "Cocoa",
                    "-I", str(OUT), str(HERE / "probe.m"), "-o", str(binary)], check=True, timeout=45)
    output = OUT / f"results-{arch}.json"
    run = subprocess.run(["arch", f"-{arch}", str(binary), str(output)], capture_output=True, text=True, timeout=60)
    (OUT / f"output-{arch}.log").write_text(run.stdout + run.stderr)
    print(f"{arch}: {run.stdout}{run.stderr}", end="", flush=True)
    run.check_returncode()
    summary["runs"].append({"architecture": arch, **json.loads(output.read_text())})
summary["probeHashes"] = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in [HERE / "probe.m", HERE / "run.py"]}
(HERE / "results.json").write_text(json.dumps(summary, indent=2) + "\n")
