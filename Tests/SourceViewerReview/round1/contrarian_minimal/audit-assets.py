#!/usr/bin/env python3
"""Measure legacy preview resources left after their only caller was deleted."""
from pathlib import Path
import json
import subprocess

repo = Path(__file__).resolve().parents[4]
project = repo / "Notation.xcodeproj/project.pbxproj"
data = json.loads(subprocess.check_output(["plutil", "-convert", "json", "-o", "-", str(project)]))
objects = data["objects"]
resources = [x for x in objects.values() if x.get("isa") == "PBXResourcesBuildPhase"]
resource_refs = {objects[x]["fileRef"] for phase in resources for x in phase["files"]}
names = ["HUDIconLock", "HUDIconPrint", "HUDIconSave", "HUDIconShare"]
code = [p for root in ("Sources", "Resources") for p in (repo / root).rglob("*")
        if p.is_file() and p.suffix in (".m", ".h", ".c", ".xib", ".nib", ".strings")]
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

orphan = repo / "Resources/Interfaces/SaveHTMLPreview.nib"
assert orphan.exists()
assert "SaveHTMLPreview" not in project.read_text()
assert b"shareNote:" in (orphan / "designable.nib").read_bytes()
assert not [p for p in code if "Sources" in p.parts and b"SaveHTMLPreview" in p.read_bytes()]
print(f"ORPHAN SHARE NIB: {sum(p.stat().st_size for p in orphan.iterdir())} bytes; no Xcode or Sources reference")
print("RESOURCE CLOSURE AUDIT COMPLETE")
