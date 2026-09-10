#!/usr/bin/env python3
"""Audit forgotten native-editing UI/preferences/import boundaries."""
import argparse
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
sys.path.insert(0, str(REPO / "Tests"))
from compiler_support import include_flags

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--app", type=Path,
                    default=REPO / "build/DerivedData/Build/Products/Development/nvALT.app")
parser.add_argument("--static-only", action="store_true")
args = parser.parse_args()

locales = ("en", "de", "fr", "it", "pt-PT", "zh")
removed_preferences = {
    "changedAutoPairing:", "changedAutoSuggestLinks:", "changedSpellChecking:",
    "changedSoftTabs:", "changedStyledTextBehavior:", "changedTabBehavior:", "changedRTL:",
}
removed_editor_actions = {
    "pasteMarkdownLink:", "shiftLeftAction:", "shiftRightAction:",
    "strikethroughNV:", "bold:", "italic:", "insertLink:",
}
native_menu_actions = {
    "toggleContinuousSpellChecking:", "toggleSmartInsertDelete:",
    "toggleAutomaticQuoteSubstitution:", "toggleAutomaticDashSubstitution:",
    "toggleAutomaticTextReplacement:",
}

static_checks = 0
for locale in locales:
    localized = REPO / "Resources" / "Localization" / f"{locale}.lproj"
    preferences = ET.parse(localized / "Preferences.xib").getroot()
    menu = ET.parse(localized / "MainMenu.xib").getroot()
    browser = ET.parse(localized / "BrowserWindow.xib").getroot()

    preference_actions = {node.attrib.get("selector") for node in preferences.iter("action")}
    assert removed_preferences.isdisjoint(preference_actions), (locale, removed_preferences & preference_actions)
    editing_panes = [node for node in preferences.iter("customView")
                     if node.attrib.get("userLabel") == "editing view"]
    assert len(editing_panes) == 1, (locale, len(editing_panes))
    editing_actions = {node.attrib.get("selector") for node in editing_panes[0].iter("action")}
    assert editing_actions == {"changedMakeURLsClickable:", "changedExternalEditorsMenu:"}, (locale, editing_actions)

    menu_actions = {node.attrib.get("selector") for node in menu.iter("action")}
    assert removed_editor_actions.isdisjoint(menu_actions), (locale, removed_editor_actions & menu_actions)
    for action in native_menu_actions:
        nodes = [node for node in menu.iter("action") if node.attrib.get("selector") == action]
        assert len(nodes) == 1 and nodes[0].attrib.get("target") == "-1", (locale, action)

    for document in (menu, browser):
        editors = [node for node in document.iter("textView")
                   if node.attrib.get("customClass") == "LinkingEditor"]
        assert len(editors) == 1, (locale, len(editors))
        assert editors[0].attrib.get("richText") == "NO"
        assert editors[0].attrib.get("importsGraphics") == "NO"
        assert editors[0].attrib.get("smartInsertDelete") == "YES"

    for xib_name in ("Preferences.xib", "MainMenu.xib", "BrowserWindow.xib"):
        with tempfile.TemporaryDirectory(prefix="native-edit-r2-xib-") as temporary:
            subprocess.run(["xcrun", "ibtool", "--compile", str(Path(temporary) / "out.nib"),
                            str(localized / xib_name)], check=True,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    static_checks += 1

global_prefs_h = (REPO / "Sources/Preferences/GlobalPrefs.h").read_text()
global_prefs_m = (REPO / "Sources/Preferences/GlobalPrefs.m").read_text()
importer = (REPO / "Sources/ImportExport/AlienNoteImporter.m").read_text()
notation_preferences = (REPO / "Sources/Preferences/NotationPrefsViewController.m").read_text()

# Formatted note imports and storage formats are already blocked at their public UI boundaries.
for extension in ("html", "webarchive", "rtf", "rtfd", "doc", "docx", "pdf"):
    assert f'@"{extension}"' in importer, extension
assert "return nil;" in importer
assert "[item tag] != SingleDatabaseFormat && [item tag] != PlainTextFormat" in notation_preferences
static_checks += 2

# Contrarian finding: the removed soft-tab width survived as an active hidden preference.
assert "- (NSInteger)numberOfSpacesInTab;" in global_prefs_h
assert 'NumberOfSpacesInTabKey = @"NumberOfSpacesInTab"' in global_prefs_m
assert "[self numberOfSpacesInTab]" in global_prefs_m
assert "removeTabStop:" in global_prefs_m and "setDefaultTabInterval:" in global_prefs_m
static_checks += 1

static_output = (
    f"PASS: localized preferences/menu/editor boundary audit ({static_checks} checks)\n"
    "FINDING: hidden NumberOfSpacesInTab still replaces AppKit paragraph tab stops\n"
)
print(static_output, end="")
if args.static_only:
    (HERE / "output.txt").write_text(static_output)
    raise SystemExit(0)
if not args.app.is_dir():
    raise SystemExit("Build the Development app or supply --app.")

with tempfile.TemporaryDirectory(prefix="native-edit-r2-contrarian-a-") as temporary:
    root = Path(temporary)
    harness = root / "Round2ContrarianA.m"
    dylib = root / "Round2ContrarianA.dylib"
    base = (REPO / "Tests/MultipleWindowsTests.m").read_text()
    prefix = base.split("- (void)nv_runTests {")[0] + "- (void)nv_runTests {"
    prefix = prefix.replace("[[self window] makeKeyAndOrderFront:self];",
                            "[NSApp activateIgnoringOtherApps:YES]; [[self window] makeKeyAndOrderFront:self];")
    support = (REPO / "Tests/SourceBackspace/support.h").read_text()
    harness.write_text(support + prefix + (HERE / "probe-body.m").read_text())
    subprocess.run([
        "xcrun", "clang", "-arch", "x86_64", "-mmacosx-version-min=10.13", "-dynamiclib",
        "-undefined", "dynamic_lookup", "-fno-objc-arc", "-Wno-deprecated-declarations",
        *include_flags(REPO), "-include", str(REPO / "Config/Notation_Prefix.pch"),
        "-framework", "Cocoa", "-framework", "Carbon", "-framework", "WebKit",
        "-o", str(dylib), str(harness),
    ], check=True)

    common_git = Path(subprocess.check_output(
        ["git", "rev-parse", "--git-common-dir"], cwd=REPO, text=True).strip())
    if not common_git.is_absolute():
        common_git = (REPO / common_git).resolve()
    lock_path = common_git.parent / "build/pr-review/gui.lock"
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    with lock_path.open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        app = root / "Round 2 Contrarian A.app"
        shutil.copytree(args.app, app, symlinks=True)
        info_path = app / "Contents/Info.plist"
        info = plistlib.loads(info_path.read_bytes())
        info["CFBundleIdentifier"] = "org.nvalt.window-tests." + uuid.uuid4().hex
        info_path.write_bytes(plistlib.dumps(info))
        for directory in ("Notes", "Support", "Temp"):
            (root / directory).mkdir()
        binary = app / "Contents/MacOS" / info["CFBundleExecutable"]
        environment = dict(os.environ, NV_WINDOW_TEST_DIRECTORY=str(root),
                           DYLD_INSERT_LIBRARIES=str(dylib), TMPDIR=str(root / "Temp") + "/")
        result = subprocess.run([
            str(binary), "-ShowDockIcon", "YES", "-StatusBarItem", "NO",
            "-QuitWhenClosingMainWindow", "NO", "-NumberOfSpacesInTab", "11",
        ], env=environment, timeout=90, stdout=subprocess.PIPE,
           stderr=subprocess.STDOUT, text=True)
        output = static_output + result.stdout
        print(result.stdout, end="")
        (HERE / "output.txt").write_text(output)
        completed = "ROUND 2 CONTRARIAN A PASSED (" in result.stdout
        raise SystemExit(0 if result.returncode == 0 and completed else result.returncode or 1)
