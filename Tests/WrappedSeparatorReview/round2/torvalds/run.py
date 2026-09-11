#!/usr/bin/env python3
"""Check Unicode neighbor edits against frozen production and fresh glyphs."""
import hashlib
import json
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
REF = "2ea92180939a3e51df8fe867ad548140ed455868"
OUT = REPO / "build/WrappedSeparatorReview/round2/torvalds"
OUT.mkdir(parents=True, exist_ok=True)
source = subprocess.check_output(["git", "show", f"{REF}:Sources/Editor/LinkingEditor.m"], cwd=REPO, text=True, timeout=15)
start = source.index("- (NSUInteger)layoutManager:")
opening = source.index("{", start)
assert "shouldGenerateGlyphs:" in source[start:opening]
end, depth = opening + 1, 1
while depth:
    depth += (source[end] == "{") - (source[end] == "}")
    end += 1
hook = source[start:end]
(OUT / "production.inc").write_text("@interface ProductionDelegate:NSObject<NSLayoutManagerDelegate>\n@end\n@implementation ProductionDelegate\n" + hook + "\n@end\n")
summary = {"reviewedCommit": REF, "callbackSHA256": hashlib.sha256(hook.encode()).hexdigest(),
           "macOS": subprocess.check_output(["sw_vers"], text=True), "xcode": subprocess.check_output(["xcodebuild", "-version"], text=True), "runs": []}
for arch in ["arm64", "x86_64"]:
    binary = OUT / f"probe-{arch}"
    subprocess.run(["xcrun", "clang", "-arch", arch, f"-mmacosx-version-min={'11.0' if arch=='arm64' else '10.13'}", "-fno-objc-arc", "-fblocks", "-Wall", "-Wextra", "-Werror", "-framework", "Cocoa", "-I", str(OUT), str(HERE / "probe.m"), "-o", str(binary)], check=True, timeout=45)
    result = OUT / f"results-{arch}.json"
    run = subprocess.run(["arch", f"-{arch}", str(binary), str(result)], capture_output=True, text=True, timeout=45)
    (OUT / f"output-{arch}.log").write_text(run.stdout + run.stderr)
    print(f"{arch}: {run.stdout}{run.stderr}", end="", flush=True)
    run.check_returncode()
    summary["runs"].append({"architecture": arch, **json.loads(result.read_text())})
summary["probeHashes"] = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in [HERE / "run.py", HERE / "probe.m"]}
(HERE / "results.json").write_text(json.dumps(summary, indent=2) + "\n")
