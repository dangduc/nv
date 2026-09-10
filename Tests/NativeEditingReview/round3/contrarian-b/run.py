#!/usr/bin/env python3
"""Round-3 adversarial probe for responder-chain routing of editor commands."""
import fcntl
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import uuid
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
APP = REPO / "build/DerivedData/Build/Products/Development/nvALT.app"
sys.path.insert(0, str(REPO / "Tests"))
from compiler_support import include_flags


def check(condition, description):
    if not condition:
        raise AssertionError(description)
    print("PASS:", description)


def structural_checks():
    for xib in sorted((REPO / "Resources/Localization").glob("*.lproj/MainMenu.xib")):
        root = ET.parse(xib).getroot()
        editors = {
            node.attrib["id"]
            for node in root.iter("textView")
            if node.attrib.get("customClass") == "LinkingEditor"
        }
        find_actions = [
            action
            for action in root.iter("action")
            if action.attrib.get("selector") == "performFindPanelAction:"
        ]
        locale = xib.parent.name
        check(len(editors) == 1, f"{locale} main nib has one embedded source editor")
        check(len(find_actions) == 5, f"{locale} main nib has five Find actions")
        check({action.attrib.get("target") for action in find_actions} == editors,
              f"{locale} legacy Find connections have one consistent retarget source")

    app = (REPO / "Sources/Application/NVApplicationController.m").read_text()
    check("[[item target] isKindOfClass:[NSView class]]" in app and
          "[item setTarget:self]" in app and
          "[self forwardTargetForSelector:[invocation selector]]" in app,
          "application controller retargets nib view actions and forwards them to the active browser")
    controller = (REPO / "Sources/Browser/AppController_Preview.m").read_text()
    check("else [textView performFindPanelAction:sender]" in controller,
          "active browser owns source/preview Find routing")


def build_probe(root):
    harness = root / "NativeEditingContrarianBR3.m"
    dylib = root / "NativeEditingContrarianBR3.dylib"
    base = (REPO / "Tests/MultipleWindowsTests.m").read_text()
    prefix = base.split("- (void)nv_runTests {")[0] + "- (void)nv_runTests {"
    prefix = prefix.replace(
        "[[self window] makeKeyAndOrderFront:self];",
        "[NSApp activateIgnoringOtherApps:YES]; [[self window] makeKeyAndOrderFront:self];",
    )
    support = (REPO / "Tests/SourceBackspace/support.h").read_text()
    harness.write_text(support + prefix + (HERE / "probe-body.m").read_text())
    subprocess.run([
        "xcrun", "clang", "-arch", "x86_64", "-mmacosx-version-min=10.13",
        "-dynamiclib", "-undefined", "dynamic_lookup", "-fno-objc-arc",
        "-Wno-deprecated-declarations", *include_flags(REPO),
        "-include", str(REPO / "Config/Notation_Prefix.pch"),
        "-framework", "Cocoa", "-framework", "Carbon", "-framework", "WebKit",
        "-o", str(dylib), str(harness),
    ], check=True)
    return dylib


def run_probe(root, dylib):
    if not APP.is_dir():
        raise SystemExit("Build the Development app before running this review.")
    common_git = Path(subprocess.check_output(
        ["git", "rev-parse", "--git-common-dir"], cwd=REPO, text=True
    ).strip())
    if not common_git.is_absolute():
        common_git = (REPO / common_git).resolve()
    lock_path = common_git.parent / "build/pr-review/gui.lock"
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    with lock_path.open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        app = root / "Native Editing Contrarian B Round 3.app"
        shutil.copytree(APP, app, symlinks=True)
        info_path = app / "Contents/Info.plist"
        info = plistlib.loads(info_path.read_bytes())
        info["CFBundleIdentifier"] = "org.nvalt.native-editing-contrarian-b-r3." + uuid.uuid4().hex
        info_path.write_bytes(plistlib.dumps(info))
        for directory in ("Notes", "Support", "Temp"):
            (root / directory).mkdir()
        binary = app / "Contents/MacOS" / info["CFBundleExecutable"]
        environment = dict(
            os.environ,
            NV_WINDOW_TEST_DIRECTORY=str(root),
            DYLD_INSERT_LIBRARIES=str(dylib),
            TMPDIR=str(root / "Temp") + "/",
        )
        result = subprocess.run(
            [str(binary), "-ShowDockIcon", "YES", "-StatusBarItem", "NO",
             "-QuitWhenClosingMainWindow", "NO"],
            env=environment, timeout=90,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
        )
        (HERE / "output.txt").write_text(result.stdout)
        print(result.stdout, end="")
        marker = "CONTRARIAN B ROUND 3 EVIDENCE PASSED (" in result.stdout
        if result.returncode != 0 or not marker:
            print(f"FAIL: app exited {result.returncode}; completion marker={marker}")
        return 0 if result.returncode == 0 and marker else 1


def main():
    structural_checks()
    with tempfile.TemporaryDirectory(prefix="nvalt-native-editing-contrarian-b-r3-") as temporary:
        root = Path(temporary)
        return run_probe(root, build_probe(root))


if __name__ == "__main__":
    raise SystemExit(main())
