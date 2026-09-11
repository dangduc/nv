#!/usr/bin/env python3
"""Bounded no-GUI UX/workflow evidence against the recorded implementation."""
from pathlib import Path
import json
import plistlib
import re
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]


def method(path, signature):
    source = (REPO / path).read_text()
    start = source.index(signature)
    end = re.search(r"\n[+-] \(", source[start + len(signature):])
    return source[start:start + len(signature) + end.start()].strip()


source = (HERE / "probe.m").read_text()
for marker, path, signature in (
    ("@NOTE_LINK@", "Sources/Model/NoteObject.m", "- (NSURL*)uniqueNoteLink"),
    ("@WIKI_LINK@", "Sources/Editor/AttributedPlainText.m", "- (void)_addDoubleBracketedNVLinkAttributesForRange:"),
    ("@CLICK_LINK@", "Sources/Editor/LinkingEditor.m", "- (void)clickedOnLink:"),
):
    source = source.replace(marker, method(path, signature))

results = {"commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=REPO, text=True).strip(), "runtime": []}
with tempfile.TemporaryDirectory(prefix="nvalt-ux-review-") as temporary:
    root = Path(temporary)
    harness = root / "Probe.m"
    binary = root / "Probe"
    harness.write_text(source)
    subprocess.run(["xcrun", "clang", "-fno-objc-arc", "-fblocks", "-Wno-deprecated-declarations",
                    "-I", str(REPO / "Sources/Application"), "-framework", "Cocoa", str(harness), "-o", str(binary)], check=True)
    imports = subprocess.check_output(["nm", "-u", str(binary)], text=True)
    for forbidden in ("_OBJC_CLASS_$_NSApplication", "_OBJC_CLASS_$_NSWorkspace", "_SecKeychain"):
        assert forbidden not in imports, forbidden
    for flavor, configuration, name in (("development", "Development", "nvALT Development"), ("release", "ForBuilding", "nvALT")):
        built = REPO / "build/DerivedData/Build/Products" / configuration / (name + ".app")
        metadata = plistlib.loads((built / "Contents/Info.plist").read_bytes())
        assert metadata["CFBundleName"] == name
        assert metadata["CFBundleExecutable"] == name
        assert (built / "Contents/MacOS" / name).is_file()
        app = root / (flavor + ".app") / "Contents"
        (app / "MacOS").mkdir(parents=True)
        shutil.copy2(binary, app / "MacOS/Probe")
        metadata.update(CFBundleExecutable="Probe", CFBundleIdentifier="org.nvalt.review.ux." + flavor)
        (app / "Info.plist").write_bytes(plistlib.dumps(metadata))
        output = subprocess.check_output([str(app / "MacOS/Probe"), flavor], text=True)
        result = json.loads(output)
        results["runtime"].append(result)
        print(f"PASS: {flavor}, {result['checks']} generated/copy-link routing checks")

# Read-only workflow checks. The documented shell path is quoted because its
# executable and bundle names include a space. No application is launched.
launch = 'open "build/DerivedData/Build/Products/Development/nvALT Development.app"'
for filename in ("README.markdown", "AGENTS.md"):
    assert launch in (REPO / filename).read_text(), filename
results["documented_launch"] = {"README.markdown": "matches built app", "AGENTS.md": "matches built app"}

# Nib/source labels are evidence of authored labels only. AppKit can rename the
# application menu at runtime; this check deliberately makes no GUI claim.
labels = {}
for path in sorted((REPO / "Resources/Localization").glob("*.lproj/MainMenu.xib")):
    tree = ET.parse(path)
    labels[path.parent.name] = [item.attrib["title"] for item in tree.findall(".//menuItem")
                               if any(action.attrib.get("selector") in ("terminate:", "orderFrontStandardAboutPanel:", "hide:")
                                      for action in item.findall("./connections/action"))]
results["authored_menu_labels"] = labels
results["browser_title_method"] = method("Sources/Browser/AppController_BrowserUI.m", "- (void)updateNoteHeader")
results["identity_limits"] = "No NSApplication or nib instantiation: runtime menu substitution and status-item distinction remain unverified."
(HERE / "results.json").write_text(json.dumps(results, indent=2) + "\n")
print("PASS: documented build/run paths match built products; menu and title evidence recorded with GUI limits")
