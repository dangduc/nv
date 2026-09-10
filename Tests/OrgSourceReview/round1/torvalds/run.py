#!/usr/bin/env python3
"""Review the native Org package with ordinary source fixtures only."""
from pathlib import Path
import hashlib
import json
import platform
import plistlib
import subprocess

here = Path(__file__).resolve().parent
root = here.parents[3]
build = root / "build/OrgSourceReview/round1/torvalds"
build.mkdir(parents=True, exist_ok=True)
vendor = root / "ThirdParty/TreeSitter"

def run(command):
    result = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=True)
    return result.stdout

output = []
metadata = {"head": run(["git", "-C", str(root), "rev-parse", "HEAD"]).strip(),
            "host": platform.platform(), "xcode": run(["xcodebuild", "-version"]).strip()}
for arch, minimum in [("x86_64", "10.13"), ("arm64", "11.0")]:
    common = ["xcrun", "clang", "-arch", arch, "-mmacosx-version-min=" + minimum,
              "-std=c11", "-O2", "-I", str(vendor / "runtime/include"),
              "-I", str(vendor / "org/src")]
    objects = []
    for name in ["NVTreeSitterRuntime", "NVTreeSitterOrg", "NVTreeSitterOrgScanner"]:
        obj = build / (arch + "-" + name + ".o")
        run(common + ["-c", str(root / "Sources/Editor/TreeSitter" / (name + ".c")), "-o", str(obj)])
        objects.append(str(obj))
    executable = build / ("probe-" + arch)
    run(common + [str(here / "probe.c")] + objects + ["-o", str(executable)])
    result = run([str(executable)])
    output.append(arch + ": " + result.strip())
    output.append(run(["xcrun", "vtool", "-show-build", str(executable)]).strip())

manifest = json.loads((vendor / "manifest.json").read_text())
assert next(c for c in manifest["components"] if c["vendored_directories"] == ["org"])["commit"] == "f15da8e8fcb3a2d764c7092ae6ba4dc87d3b3093"
for path, recorded in manifest["files"].items():
    content = (vendor / path).read_bytes()
    assert len(content) == recorded["bytes"], path
    assert hashlib.sha256(content).hexdigest() == recorded["sha256"], path
output.append("PASS: all vendored file sizes and hashes match the manifest")

upstream = root / "build/OrgInvestigation/tree-sitter-org-next"
upstream_commit = "f15da8e8fcb3a2d764c7092ae6ba4dc87d3b3093"
if upstream.exists():
    for relative in ["LICENSE", "src/parser.c", "src/scanner.c", "src/tree_sitter/parser.h", "src/tree_sitter/alloc.h", "src/tree_sitter/array.h"]:
        upstream_bytes = subprocess.check_output(["git", "-C", str(upstream), "show", upstream_commit + ":" + relative])
        assert upstream_bytes == (vendor / "org" / relative).read_bytes(), relative
    output.append("PASS: six Org vendored files match the recorded upstream commit byte for byte")

bundle = root / "build/DerivedData/Build/Products/Development/nvALT.app/Contents"
assert (bundle / "Resources/Syntax/org.scm").read_bytes() == (root / "Resources/Syntax/org.scm").read_bytes()
assert (vendor / "org/LICENSE").read_text() in (bundle / "Resources/Syntax/ThirdPartyNotices.txt").read_text()
info = plistlib.loads((bundle / "Info.plist").read_bytes())
assert "org" in info["CFBundleDocumentTypes"][0]["CFBundleTypeExtensions"]
assert "net.notational.org-source" in info["CFBundleDocumentTypes"][0]["LSItemContentTypes"]
declaration = next(d for d in info["UTImportedTypeDeclarations"] if d["UTTypeIdentifier"] == "net.notational.org-source")
assert "public.plain-text" in declaration["UTTypeConformsTo"]
assert "org" in declaration["UTTypeTagSpecification"]["public.filename-extension"]
output.append("PASS: built app carries the exact Org query, license notice and document-type registration")
output.append(run(["xcrun", "vtool", "-show-build", str(bundle / "MacOS/nvALT")]).strip())
metadata["bundle_binary_sha256"] = hashlib.sha256((bundle / "MacOS/nvALT").read_bytes()).hexdigest()
(here / "metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")
(here / "output.txt").write_text("\n\n".join(output) + "\n")
print("\n\n".join(output))
