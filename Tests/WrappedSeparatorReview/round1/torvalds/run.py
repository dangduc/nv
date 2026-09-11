#!/usr/bin/env python3
"""Bounded callback-contract and native fallback review of frozen glyph hooks."""
import hashlib
import json
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
CURRENT = "9e6c8dd6adc058e7044f2c562532af97dd4e63d4"
BASE = "75d6f42"
OUT = REPO / "build/WrappedSeparatorReview/round1/torvalds"
OUT.mkdir(parents=True, exist_ok=True)

def callback(ref):
    source = subprocess.check_output(["git", "show", f"{ref}:Sources/Editor/LinkingEditor.m"], cwd=REPO, text=True, timeout=15)
    start = source.index("- (NSUInteger)layoutManager:")
    opening = source.index("{", start)
    assert "shouldGenerateGlyphs:" in source[start:opening]
    end, depth = opening + 1, 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]

hooks = {"PreviousDelegate": callback(BASE), "CurrentDelegate": callback(CURRENT)}
generated = "#define malloc ReviewMalloc\n#define free ReviewFree\n"
for name, method in hooks.items():
    generated += f"@interface {name}:NSObject<NSLayoutManagerDelegate>\n@end\n@implementation {name}\n{method}\n@end\n"
generated += "#undef malloc\n#undef free\n"
(OUT / "production-hooks.inc").write_text(generated)
summary = {"reviewedCommit": CURRENT, "baseCommit": subprocess.check_output(["git", "rev-parse", BASE], cwd=REPO, text=True).strip(),
           "callbackHashes": {name: hashlib.sha256(body.encode()).hexdigest() for name, body in hooks.items()},
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
summary["probeHashes"] = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in [HERE / "probe.m", HERE / "run.py"]}
(HERE / "results.json").write_text(json.dumps(summary, indent=2) + "\n")
