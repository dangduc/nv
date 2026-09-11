#!/usr/bin/env python3
"""Compare two focused editor sequences before and after paragraph cleanup."""
import hashlib
import json
from pathlib import Path
import platform
import subprocess
import tempfile

suite = Path(__file__).resolve().parent
repo = suite.parents[3]
source = repo / "Sources/Editor/NVSourceTypesetter.m"
frozen = "4c8f6b449504a50caa460d78efebd42b94beaba6"
previous = "4b049709b2cecc6eac80514586ccacc119d12802"
assert subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip() == frozen
assert source.read_bytes() == subprocess.check_output(["git", "show", frozen + ":Sources/Editor/NVSourceTypesetter.m"], cwd=repo)
# Reuse the existing brace scanner for the actual editor glyph callback.
existing = (repo / "Tests/WordWrapping/run.py").read_text()
namespace = {}
exec(existing[existing.index("def glyph_delegate("):existing.index("parser = argparse")], namespace)
hook = namespace["glyph_delegate"]((repo / "Sources/Editor/LinkingEditor.m").read_text())
runs = []
with tempfile.TemporaryDirectory(prefix="nvalt-r2-ux-") as temporary:
    output = Path(temporary)
    (output / "production-space-delegate.h").write_text(
        "@interface SpaceDelegate : NSObject <NSLayoutManagerDelegate>\n@end\n@implementation SpaceDelegate\n" + hook + "\n@end\n")
    old_source = output / "previous-typesetter.m"
    old_source.write_bytes(subprocess.check_output(["git", "show", previous + ":Sources/Editor/NVSourceTypesetter.m"], cwd=repo))
    for arch in (["arm64", "x86_64"] if platform.machine() == "arm64" else ["x86_64"]):
        for mode, implementation in (("corrected", source), ("previous-cache-lifetime-control", old_source)):
            label = arch + "-" + mode
            binary = output / label
            result = output / (label + ".json")
            subprocess.run(["xcrun", "clang", "-arch", arch,
                "-mmacosx-version-min=" + ("11.0" if arch == "arm64" else "10.13"),
                "-fno-objc-arc", "-Wno-deprecated-declarations", "-Wall", "-Wextra", "-Wno-unused-parameter",
                "-framework", "Cocoa", "-framework", "CoreText", "-I", str(output), "-I", str(source.parent),
                str(suite / "probe.m"), str(implementation), "-o", str(binary)], check=True)
            run = subprocess.run(["arch", "-" + arch, str(binary), str(result)], capture_output=True, text=True, timeout=60)
            print(label + ": " + run.stdout + run.stderr, end="")
            run.check_returncode()
            record = json.loads(result.read_text())
            transcript = record.pop("transcript")
            record["transcript_sha256"] = hashlib.sha256(json.dumps(transcript, sort_keys=True).encode()).hexdigest()
            record.update(architecture=arch, mode=mode, source_sha256=hashlib.sha256(implementation.read_bytes()).hexdigest())
            runs.append(record)
(suite / "results.json").write_text(json.dumps({"revision":frozen,"previous_revision":previous,
    "host":platform.mac_ver()[0],"runs":runs},indent=2)+"\n")
for current, old in zip(runs[::2], runs[1::2]):
    assert current["failures"] == old["failures"] == 0, (current["failureKinds"], old["failureKinds"])
    assert current["retainedAnalysisCallbacks"] == 0 and old["retainedAnalysisCallbacks"] > 0
    assert current["transcript_sha256"] == old["transcript_sha256"], "Cleanup changed editor geometry or selection."
