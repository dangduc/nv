#!/usr/bin/env python3
"""Run independent source-editor geometry probes against the frozen production code."""
import hashlib
import json
from pathlib import Path
import platform
import subprocess
import tempfile

suite = Path(__file__).resolve().parent
repo = suite.parents[3]
source = repo / "Sources/Editor/NVSourceTypesetter.m"
editor = (repo / "Sources/Editor/LinkingEditor.m").read_text()
start = editor.index("- (NSUInteger)layoutManager:")
end = editor.index("{", start) + 1
depth = 1
while depth:
    depth += (editor[end] == "{") - (editor[end] == "}")
    end += 1
hook = editor[start:end]
assert "shouldGenerateGlyphs:" in hook
runs = []
with tempfile.TemporaryDirectory(prefix="nvalt-contrarian-ux-") as temp:
    output = Path(temp)
    (output / "production-space-delegate.h").write_text(
        "@interface SpaceDelegate : NSObject <NSLayoutManagerDelegate>\n@end\n"
        "@implementation SpaceDelegate\n" + hook + "\n@end\n")
    for arch in (["arm64", "x86_64"] if platform.machine() == "arm64" else ["x86_64"]):
        binary = output / ("probe-" + arch)
        subprocess.run(["xcrun", "clang", "-arch", arch,
            "-mmacosx-version-min=" + ("11.0" if arch == "arm64" else "10.13"),
            "-fno-objc-arc", "-Wno-deprecated-declarations", "-Wall", "-Wextra", "-Wno-unused-parameter",
            "-framework", "Cocoa", "-framework", "CoreText", "-I", str(output),
            "-I", str(source.parent), str(suite / "probe.m"), str(source), "-o", str(binary)], check=True)
        for control in (False, True):
            label = arch + ("-previous-character-control" if control else "")
            result = output / (label + ".json")
            run = subprocess.run(["arch", "-" + arch, str(binary), str(result)] + (["control"] if control else []),
                capture_output=True, text=True, timeout=120)
            print(label + ": " + run.stdout + run.stderr, end="")
            run.check_returncode()
            record = json.loads(result.read_text())
            record["architecture"] = arch
            record["mode"] = "previous-character-control" if control else "production"
            runs.append(record)
(suite / "results.json").write_text(json.dumps({
    "revision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip(),
    "typesetter_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
    "host": platform.mac_ver()[0], "runs": runs}, indent=2) + "\n")
for record in runs:
    if record["mode"] == "production":
        assert record["failures"] == 0, record["failureKinds"]
    else:
        assert record["failures"] > 0, "Native character layout must split fitting words."
        assert set(record["failureKinds"]) == {"fitting ordinary word remains whole"}, record["failureKinds"]
