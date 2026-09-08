#!/usr/bin/env python3
"""Measure legacy preview resources left after their only caller was deleted."""
from pathlib import Path
import argparse
import json
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--expect-removed", action="store_true", help="Verify the fixed source tree and built app instead of the original finding")
parser.add_argument("--source-only", action="store_true", help="Skip the built app until a clean build is available")
args = parser.parse_args()
if args.source_only and not args.expect_removed:
    parser.error("--source-only requires --expect-removed")

repo = Path(__file__).resolve().parents[4]
project = repo / "Notation.xcodeproj/project.pbxproj"
data = json.loads(subprocess.check_output(["plutil", "-convert", "json", "-o", "-", str(project)]))
objects = data["objects"]
resources = [x for x in objects.values() if x.get("isa") == "PBXResourcesBuildPhase"]
resource_refs = {objects[x]["fileRef"] for phase in resources for x in phase["files"]}
names = ["HUDIconLock", "HUDIconPrint", "HUDIconSave", "HUDIconShare"]
code = [p for root in ("Sources", "Resources") for p in (repo / root).rglob("*")
        if p.is_file() and p.suffix in (".m", ".h", ".c", ".xib", ".nib", ".strings")]
orphan = repo / "Resources/Interfaces/SaveHTMLPreview.nib"
if args.expect_removed:
    bundle = repo / "build/DerivedData/Build/Products/Development/nvALT.app/Contents/Resources"
    if not args.source_only:
        assert bundle.is_dir(), "Build the Development app before checking its resources"
    for name in names:
        assert not (repo / "Resources/Images" / (name + ".png")).exists(), name + " remains in the source tree"
        assert name not in project.read_text(), name + " remains in the Xcode project"
        assert not [p for p in code if name.encode() in p.read_bytes()], name + " still has a code or interface reference"
        if not args.source_only:
            assert not list(bundle.rglob(name + ".png")), name + " remains in the built app; use a clean build"
        print("REMOVED RESOURCE VERIFIED:", name)
    assert not orphan.exists(), "The orphan sharing nib remains in the source tree"
    assert "SaveHTMLPreview" not in project.read_text(), "The sharing nib remains in the Xcode project"
    assert not [p for p in code if "Sources" in p.parts and b"SaveHTMLPreview" in p.read_bytes()]
    if not args.source_only:
        assert not list(bundle.rglob("SaveHTMLPreview.nib")), "The sharing nib remains in the built app"
    print("REMOVED SHARING NIB VERIFIED")
    print("RESOURCE REMOVAL AUDIT COMPLETE (" + ("source only" if args.source_only else "source and built app") + ")")
    raise SystemExit(0)

total = 0
for name in names:
    asset = repo / "Resources/Images" / (name + ".png")
    shipped = repo / "build/DerivedData/Build/Products/Development/nvALT.app/Contents/Resources" / asset.name
    refs = [key for key, value in objects.items() if value.get("path") == asset.name]
    assert len(refs) == 1 and refs[0] in resource_refs, name + " must be in the Resources phase"
    callers = [str(p.relative_to(repo)) for p in code if name.encode() in p.read_bytes()]
    assert not callers, (name, callers)
    assert shipped.read_bytes() == asset.read_bytes(), name + " must be copied into the built app"
    # A baseline caller proves that the removed workflow, rather than an
    # unrelated older dead asset, accounts for its remaining resource entry.
    previous = subprocess.check_output(["git", "show", "origin/master:Resources/Localization/en.lproj/MarkupPreview.xib"], cwd=repo)
    assert name.encode() in previous, name + " must have been used by the old provider"
    total += asset.stat().st_size
    print(f"UNUSED SHIPPED RESOURCE {asset.relative_to(repo)}: {asset.stat().st_size} bytes; no code or interface caller; former MarkupPreview.xib caller removed")
print(f"TOTAL UNUSED SHIPPED PNG BYTES: {total}")

assert orphan.exists()
assert "SaveHTMLPreview" not in project.read_text()
assert b"shareNote:" in (orphan / "designable.nib").read_bytes()
assert not [p for p in code if "Sources" in p.parts and b"SaveHTMLPreview" in p.read_bytes()]
print(f"ORPHAN SHARE NIB: {sum(p.stat().st_size for p in orphan.iterdir())} bytes; no Xcode or Sources reference")
print("RESOURCE CLOSURE AUDIT COMPLETE")
