#!/usr/bin/env python3
"""Compile isolated Foundation renderer checks with disposable converter fixtures."""
from pathlib import Path
import os
import plistlib
import shutil
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[3]
with tempfile.TemporaryDirectory(prefix="nvalt-source-viewers-") as temporary:
    root = Path(temporary)
    bundle = root / "Converters.bundle"
    resources = bundle / "Contents/Resources"
    resources.mkdir(parents=True)
    (bundle / "Contents/Info.plist").write_bytes(plistlib.dumps({
        "CFBundleIdentifier": "org.nvalt.tests.source-viewers",
        "CFBundlePackageType": "BNDL",
    }))
    shutil.copy2(repo / "ThirdParty/MultiMarkdown/multimarkdown", resources / "multimarkdown")
    shutil.copytree(repo / "ThirdParty/Textile_2.12", resources / "Textile_2.12")
    shutil.copy2(repo / "ThirdParty/OrgPreview/nv-org-preview", resources / "nv-org-preview")
    shutil.copy2(repo / "Tests/Regression/org-preview/core.org", resources / "org-fixture.org")
    binary = root / "RendererTests"
    subprocess.run([
        "xcrun", "clang", "-arch", "x86_64", "-mmacosx-version-min=10.13",
        "-fno-objc-arc", "-fblocks", "-lxml2", "-I", str(Path(subprocess.check_output(["xcrun", "--show-sdk-path"], text=True).strip()) / "usr/include/libxml2"), "-Wno-deprecated-declarations", "-framework", "Foundation",
        "-I", str(repo / "Sources/Preview"),
        str(repo / "Sources/Preview/NVNoteContentSnapshot.m"),
        str(repo / "Sources/Preview/NVMarkupRenderer.m"),
        str(Path(__file__).with_name("renderer-tests.m")), "-o", str(binary),
    ], check=True)
    subprocess.run([str(binary), str(bundle)], check=True, timeout=40)
