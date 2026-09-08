#!/usr/bin/env python3
"""Verify the removed workflow stays absent and retained render dependencies close."""
from pathlib import Path
import hashlib
import json
import subprocess

repo = Path(__file__).resolve().parents[4]
bundle = repo / "build/DerivedData/Build/Products/Development/nvALT.app/Contents/Resources"
project = repo / "Notation.xcodeproj/project.pbxproj"
objects = json.loads(subprocess.check_output(["plutil", "-convert", "json", "-o", "-", str(project)]))["objects"]
parents = {child: key for key, value in objects.items() for child in value.get("children", [])}
resource_phases = [phase for phase in objects.values() if phase.get("isa") == "PBXResourcesBuildPhase" or (phase.get("isa") == "PBXCopyFilesBuildPhase" and str(phase.get("dstSubfolderSpec")) == "7")]
resources = [objects[file]["fileRef"] for phase in resource_phases for file in phase["files"]]

def source_path(key):
    obj = objects[key]
    assert obj.get("sourceTree", "<group>") in ("<group>", "SOURCE_ROOT"), obj
    root = repo if obj.get("sourceTree") == "SOURCE_ROOT" or key not in parents else source_path(parents[key])
    return root / obj.get("path", "")

removed = ["HUDIconLock", "HUDIconPrint", "HUDIconSave", "HUDIconShare", "MarkupPreview", "SaveHTMLPreview", "tp2md.rb", "templateclean.html", "customclean.css", "Markdown_1.0.1"]
for name in removed:
    assert name not in project.read_text(), f"removed workflow has an Xcode reference: {name}"
    retained = [str(p.relative_to(repo)) for folder in ("Resources", "ThirdParty") for p in (repo / folder).rglob("*") if name in p.name]
    assert not retained, (name, retained)
    shipped = [str(p.relative_to(bundle)) for p in bundle.rglob("*") if name in p.name]
    assert not shipped, (name, shipped)
    print("REMOVED workflow resource absent from source, project, and built app:", name)

verified = 0
for filename in ("multimarkdown", "Textile_2.12", "Syntax"):
    refs = [key for key, value in objects.items() if value.get("isa") == "PBXFileReference" and value.get("path") == filename]
    assert len(refs) == 1 and resources.count(refs[0]) == 1, filename + " must have exactly one Resources copy entry"
    source = source_path(refs[0])
    assert source.exists(), str(source)
    source_files = [source] if source.is_file() else sorted(p for p in source.rglob("*") if p.is_file())
    relative_files = {str(p.relative_to(source)) for p in source_files} if source.is_dir() else {"."}
    shipped_root = bundle / filename
    if source.is_dir():
        shipped_files = {str(p.relative_to(shipped_root)) for p in shipped_root.rglob("*") if p.is_file()}
        assert relative_files == shipped_files, (filename, relative_files ^ shipped_files)
    for path in source_files:
        shipped = shipped_root / path.relative_to(source) if source.is_dir() else shipped_root
        assert hashlib.sha256(path.read_bytes()).digest() == hashlib.sha256(shipped.read_bytes()).digest(), str(shipped)
        verified += 1
    print("RESOURCE closure and bytes match:", filename, len(source_files), "files")

cases = [
    ([str(bundle / "multimarkdown")], b"# Minimal review marker\n\n**retained renderer**\n", [b"<h1", b"Minimal review marker", b"<strong>retained renderer</strong>"]),
    (["/usr/bin/perl", str(bundle / "Textile_2.12/textilize.pl")], b"h1. Minimal review marker\n\n*retained renderer*\n", [b"<h1", b"Minimal review marker", b"<strong>retained renderer</strong>"]),
]
for arguments, source, expected in cases:
    result = subprocess.run(arguments, input=source, cwd="/private/tmp", capture_output=True, timeout=10, check=True)
    for marker in expected:
        assert marker in result.stdout, (arguments, marker, result.stdout, result.stderr)
    print("RETAINED renderer works from unrelated working directory:", Path(arguments[-1]).name)
print(f"RESOURCE CLOSURE CHECKS PASSED: {len(removed)} removed names, {verified} retained files, {len(cases)} native helper executions")
