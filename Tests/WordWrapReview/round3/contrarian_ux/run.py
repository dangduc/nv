#!/usr/bin/env python3
"""Exercise remaining word and paragraph selection affordances in native Cocoa."""
import hashlib
import json
from pathlib import Path
import platform
import subprocess
import tempfile

suite = Path(__file__).resolve().parent
repo = suite.parents[3]
source = repo / "Sources/Editor/NVSourceTypesetter.m"
frozen = "63911bf2c66d438f178b43a8b9e996787e29acc9"
assert subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip() == frozen
assert source.read_bytes() == subprocess.check_output(["git", "show", frozen + ":Sources/Editor/NVSourceTypesetter.m"], cwd=repo)
# Reuse the production callback scanner already used by the earlier rounds.
existing = (repo / "Tests/WordWrapping/run.py").read_text()
namespace = {}
exec(existing[existing.index("def glyph_delegate("):existing.index("parser = argparse")], namespace)
hook = namespace["glyph_delegate"]((repo / "Sources/Editor/LinkingEditor.m").read_text())
runs = []
with tempfile.TemporaryDirectory(prefix="nvalt-r3-ux-") as temporary:
    output = Path(temporary)
    (output / "production-space-delegate.h").write_text(
        "@interface SpaceDelegate : NSObject <NSLayoutManagerDelegate>\n@end\n@implementation SpaceDelegate\n" + hook + "\n@end\n")
    for arch in (["arm64", "x86_64"] if platform.machine() == "arm64" else ["x86_64"]):
        binary = output / arch
        result = output / (arch + ".json")
        subprocess.run(["xcrun", "clang", "-arch", arch,
            "-mmacosx-version-min=" + ("11.0" if arch == "arm64" else "10.13"),
            "-fno-objc-arc", "-Wno-deprecated-declarations", "-Wall", "-Wextra", "-Wno-unused-parameter",
            "-framework", "Cocoa", "-framework", "CoreText", "-I", str(output), "-I", str(source.parent),
            str(suite / "probe.m"), str(source), "-o", str(binary)], check=True)
        run = subprocess.run(["arch", "-" + arch, str(binary), str(result)], capture_output=True, text=True, timeout=60)
        print(arch + ": " + run.stdout + run.stderr, end="")
        run.check_returncode()
        record = json.loads(result.read_text())
        observations = record.pop("observations")
        record["observations_sha256"] = hashlib.sha256(json.dumps(observations, sort_keys=True).encode()).hexdigest()
        record["architecture"] = arch
        runs.append(record)
(suite / "results.json").write_text(json.dumps({"revision":frozen,"source_sha256":hashlib.sha256(source.read_bytes()).hexdigest(),
    "host":platform.mac_ver()[0],"runs":runs},indent=2)+"\n")
for record in runs:
    assert record["failures"] == 0, record["failureKinds"]
