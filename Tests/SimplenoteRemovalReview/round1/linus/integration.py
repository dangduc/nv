#!/usr/bin/env python3
"""Independently check Xcode build-input closure and generate a native nib manifest."""
import json
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
BASE = "9693356"
APP = ROOT / "build/SimplenoteRemovalReview/round1.app"
BASE_APP = ROOT / "build/SyntaxFlickerReview/fix.app"
checks = 0


def command(*args):
    return subprocess.check_output(args, cwd=ROOT, text=True)


def check(condition, description):
    global checks
    assert condition, description
    checks += 1
    print("PASS:", description)


print("reviewed SHA:", command("git", "rev-parse", "HEAD").strip())
project = json.loads(command("plutil", "-convert", "json", "-o", "-", "Notation.xcodeproj/project.pbxproj"))
objects = project["objects"]
paths = {}


def visit(key, parent):
    obj = objects[key]
    tree = obj.get("sourceTree", "<group>")
    path = obj.get("path", "")
    if tree == "<group>":
        resolved = parent / path
    elif tree == "SOURCE_ROOT":
        resolved = ROOT / path
    else:
        resolved = None  # SDK/framework/build-product paths are external inputs.
    paths[key] = resolved
    for child in obj.get("children", []):
        visit(child, resolved or parent)


visit(objects[project["rootObject"]]["mainGroup"], ROOT)
tracked = set(command("git", "ls-files").splitlines())
inputs = []
for obj in objects.values():
    if obj["isa"] not in ("PBXSourcesBuildPhase", "PBXResourcesBuildPhase", "PBXCopyFilesBuildPhase"):
        continue
    for key in obj["files"]:
        file_key = objects[key]["fileRef"]
        ref = objects[file_key]
        leaves = ref.get("children", [file_key]) if ref["isa"] == "PBXVariantGroup" else [file_key]
        for leaf in leaves:
            path = paths.get(leaf)
            if path is None:
                continue
            relative = path.relative_to(ROOT).as_posix()
            inputs.append(relative)
            check(path.exists(), "build input exists: " + relative)
            check(relative in tracked or any(x.startswith(relative + "/") for x in tracked),
                  "build input belongs to checkout: " + relative)
check(not any("Sync/" in x or "SimperiumConfig" in x for x in inputs), "build phases contain no removed sync input")

deleted = command("git", "diff", "--name-only", "--diff-filter=D", BASE, "HEAD", "--", "Resources/Images").splitlines()
bundle_names = {p.name for p in APP.rglob("*")}
check(all(Path(p).name not in bundle_names for p in deleted), f"all {len(deleted)} removed sync images are absent from built app")

binary = APP / "Contents/MacOS/nvALT"
symbols = command("nm", "-j", str(binary))
base_symbols = command("nm", "-j", str(BASE_APP / "Contents/MacOS/nvALT"))
removed_classes = ["SimplenoteSession", "SimplenoteEntryCollector", "SyncResponseFetcher", "SyncSessionController"]
for name in removed_classes:
    check("_OBJC_CLASS_$_" + name in base_symbols, "positive control: old executable contains class " + name)
    check("_OBJC_CLASS_$_" + name not in symbols, "removed class absent from executable: " + name)
category_symbol = "-[NotationController(NotationSyncServiceManager) startSyncServices]"
check(category_symbol in base_symbols, "positive control: old executable contains sync-manager category method")
check("NotationController(NotationSyncServiceManager)" not in symbols, "sync-manager category methods absent from executable")
linked = command("otool", "-L", str(binary))
for name in ("SystemConfiguration", "IOKit"):
    check(name + ".framework" not in linked, "removed direct framework dependency: " + name)
deps = sorted((ROOT / "build/DerivedData/Build/Intermediates.noindex/Notation.build/Development/Notation.build/Objects-normal/x86_64").glob("*.d"))
check(len(deps) > 100, "compiled dependency records available")
check(all("SimperiumConfig" not in p.read_text() for p in deps), f"{len(deps)} compiled dependency records do not require sync configuration")
workflow = (ROOT / ".github/workflows/macos.yml").read_text()
check("SimperiumConfig" not in workflow, "CI no longer copies a removed config")

manifest = []
for relative in sorted(x for x in inputs if x.endswith("/NotationPrefsView.xib")):
    path = ROOT / relative
    root = ET.parse(path).getroot()
    old_path = str(Path(relative).with_suffix(".nib") / "designable.nib")
    old_root = ET.fromstring(command("git", "show", BASE + ":" + old_path))
    def connection_set(tree):
        return {(x.tag, tuple(sorted(x.attrib.items()))) for x in tree.iter() if x.tag in ("outlet", "action")}
    old_connections, new_connections = connection_set(old_root), connection_set(root)
    removed_connections = old_connections - new_connections
    sync_names = {"visitSimplenoteSite:", "syncFrequencyChange:", "toggledSyncing:", "webOptionsWindow",
                  "verifyStatusImageView", "verifyStatusField", "syncingFrequency", "enabledSyncButton",
                  "syncEncAlertView", "syncEncAlertField", "syncAccountField", "syncPasswordField"}
    check(not new_connections - old_connections, "retained connections have unchanged targets and IDs: " + relative)
    check(all(dict(attrs).get("property", dict(attrs).get("selector")) in sync_names
              for _, attrs in removed_connections), "only retired sync connections were removed: " + relative)
    def connections_resolve(tree):
        ids = {x.get("id") for x in tree.iter() if x.get("id")}
        connections = list(tree.iter("outlet")) + list(tree.iter("action"))
        return all(x.get("destination", x.get("target")) in ids for x in connections)
    check(connections_resolve(root), "all connection destinations resolve: " + relative)
    mutated = ET.fromstring(ET.tostring(root))
    next(mutated.iter("outlet")).set("destination", "deleted-sync-control-negative-control")
    check(not connections_resolve(mutated), "negative control: dangling outlet mutation is rejected: " + relative)
    tabs = [x.get("identifier") for x in root.iter("tabViewItem")]
    check(tabs == ["storage", "security"], "only Storage/Security tabs remain: " + relative)
    owner = next(x for x in root.iter("customObject") if x.get("id") == "-2")
    outlets = [x.get("property") for x in owner.iter("outlet")]
    selectors = [x.get("selector") for x in root.iter("action") if x.get("target") == "-2"]
    manifest.append({"locale": path.parent.name, "outlets": outlets, "selectors": selectors})
check(len(manifest) == 6, "six localized prefs XIBs are target resources")
(HERE / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
print(f"PASS: {checks} integration assertions; {len(inputs)} build inputs; {len(deps)} compiler records; six-locale native manifest generated")
