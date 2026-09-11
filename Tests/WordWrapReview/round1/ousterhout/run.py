#!/usr/bin/env python3
"""Probe the production typesetter's cache and per-layout ownership without windows."""
import hashlib
import json
from pathlib import Path
import platform
import subprocess

repo = Path(__file__).resolve().parents[4]
suite = Path(__file__).parent
out = repo / "build/WordWrapReview/round1/ousterhout"
out.mkdir(parents=True, exist_ok=True)
# Extract the actual production glyph hook, using the existing harness's brace scanner.
existing = (repo / "Tests/WordWrapping/run.py").read_text()
helper = existing[existing.index("def glyph_delegate("):existing.index("parser = argparse")]
namespace = {}
exec(helper, namespace)
hook = namespace["glyph_delegate"]((repo / "Sources/Editor/LinkingEditor.m").read_text())
(out / "space-delegate.h").write_text("@interface SpaceDelegate : NSObject <NSLayoutManagerDelegate>\n@end\n@implementation SpaceDelegate\n" + hook + "\n@end\n")
results = []
for architecture in (["arm64", "x86_64"] if platform.machine() == "arm64" else ["x86_64"]):
    binary = out / ("probe-" + architecture)
    subprocess.run(["xcrun", "clang", "-arch", architecture, "-mmacosx-version-min=" + ("11.0" if architecture == "arm64" else "10.13"),
        "-fno-objc-arc", "-Wno-deprecated-declarations", "-Wall", "-Wextra", "-Wno-unused-parameter",
        "-framework", "Cocoa", "-framework", "CoreText", "-I", str(out), "-I", str(repo / "Sources/Editor"),
        str(suite / "probe.m"), str(repo / "Sources/Editor/NVSourceTypesetter.m"), "-o", str(binary)], check=True)
    for experiment in (False, True):
        label = architecture + ("-cleanup-experiment" if experiment else "")
        result_path = out / (label + ".json")
        result = subprocess.run(["arch", "-" + architecture, str(binary), str(result_path)] + (["cleanup"] if experiment else []), capture_output=True, text=True, timeout=90)
        (out / (label + ".log")).write_text(result.stdout + result.stderr)
        print(label + ": " + result.stdout + result.stderr, end="")
        result.check_returncode()
        record = json.loads(result_path.read_text())
        record["architecture"] = architecture
        results.append(record)
record = {"revision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip(),
    "typesetter_sha256": hashlib.sha256((repo / "Sources/Editor/NVSourceTypesetter.m").read_bytes()).hexdigest(), "runs": results}
(suite / "results.json").write_text(json.dumps(record, indent=2) + "\n")
