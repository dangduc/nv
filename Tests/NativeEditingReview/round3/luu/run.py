#!/usr/bin/env python3
"""Final adversarial audit of nvALT source editing against NSTextView."""
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
    project_path = REPO / "Notation.xcodeproj/project.pbxproj"
    project = project_path.read_text()
    removed_ibeam = REPO / "Resources/Images/IBeamInverted.png"
    check(not removed_ibeam.exists() and project.count("IBeamInverted.png") == 4,
          "reproduced: the deleted I-beam asset remains in four Xcode project entries")

    source_paths = [
        path for path in (REPO / "Sources").rglob("*")
        if path.suffix in {".h", ".m", ".c", ".mm"}
    ]
    source = "\n".join(path.read_text(errors="ignore") for path in source_paths)
    retired = (
        "CheckSpellingInNoteBody", "TextReplacementInNoteBody",
        "TabKeyIndents", "PastePreservesStyle", "AutoFormatsListBullets",
        "AutoSuggestLinks", "AutoIndentsNewLines", "UseSoftTabs",
        "NumberOfSpacesInTab", "UseAutoPairing", "UseSmartInsertDelete",
        "changedTabBehavior:", "changedSpellChecking:",
        "changedAutoSuggestLinks:", "changedSoftTabs:",
        "changedAutoPairing:", "changedRTL:", "pasteMarkdownLink:",
        "shiftLeftAction:", "shiftRightAction:", "strikethroughNV:",
    )
    for token in retired:
        check(token not in source, f"production source omits retired behavior {token}")

    editor_source = (REPO / "Sources/Editor/LinkingEditor.m").read_text()
    for signature in (
        "- (void)keyDown:", "- (void)flagsChanged:",
        "- (void)deleteBackward:", "- (void)deleteForward:",
        "- (void)insertTab:", "- (void)insertBacktab:",
        "- (BOOL)performKeyEquivalent:", "- (void)complete:",
    ):
        check(signature not in editor_source,
              f"LinkingEditor does not declare {signature}")

    expected_edit_actions = {
        "undo:", "redo:", "cut:", "copy:", "paste:", "delete:",
        "selectAll:", "showGuessPanel:", "checkSpelling:",
        "toggleContinuousSpellChecking:", "orderFrontSubstitutionsPanel:",
        "toggleSmartInsertDelete:", "toggleAutomaticQuoteSubstitution:",
        "toggleAutomaticDashSubstitution:", "toggleAutomaticLinkDetection:",
        "toggleAutomaticTextReplacement:", "uppercaseWord:",
        "lowercaseWord:", "capitalizeWord:",
    }
    retired_labels = (
        "Soft tabs (spaces)", "Suggest titles for note-links", "Right-To-Left (RTL)",
        "Indent lines", "Auto-pair:", "Tab Key:", "Spelling:", "Styled Text:",
    )
    localization = REPO / "Resources/Localization"
    for locale in ("en", "de", "fr", "it", "pt-PT", "zh"):
        root = localization / f"{locale}.lproj"
        main = ET.parse(root / "MainMenu.xib").getroot()
        browser = ET.parse(root / "BrowserWindow.xib").getroot()
        preferences = ET.parse(root / "Preferences.xib").getroot()
        for name, document in (("MainMenu", main), ("BrowserWindow", browser)):
            editors = [node for node in document.iter("textView")
                       if node.attrib.get("customClass") == "LinkingEditor"]
            check(len(editors) == 1, f"{locale} {name} has one source editor")
            check(editors[0].attrib.get("richText") == "NO" and
                  editors[0].attrib.get("importsGraphics") == "NO" and
                  editors[0].attrib.get("smartInsertDelete") == "YES",
                  f"{locale} {name} source editor uses plain native defaults")

        actions = {action.attrib.get("selector") for action in main.iter("action")}
        check(expected_edit_actions <= actions,
              f"{locale} menu retains the standard Text actions")
        find_items = [item for item in main.iter("menuItem")
                      if any(action.attrib.get("selector") == "performFindPanelAction:"
                             for action in item.findall("./connections/action"))]
        check({item.attrib.get("tag") for item in find_items} == {"1", "2", "3", "7", "12"},
              f"{locale} Find menu exposes the supported native actions")

        preferences_xml = ET.tostring(preferences, encoding="unicode")
        for label in retired_labels:
            check(label not in preferences_xml,
                  f"{locale} Preferences omits retired control {label}")

        help_text = (root / "Excruciatingly Useful Shortcuts.nvhelp").read_text()
        check("macOS" in help_text, f"{locale} help includes native editing guidance")


def build_probe(root):
    harness = root / "NativeEditingLuuR3.m"
    dylib = root / "NativeEditingLuuR3.dylib"
    base = (REPO / "Tests/MultipleWindowsTests.m").read_text()
    prefix = base.split("- (void)nv_runTests {")[0] + "- (void)nv_runTests {"
    prefix = prefix.replace(
        "[[self window] makeKeyAndOrderFront:self];",
        "[NSApp activateIgnoringOtherApps:YES]; [[self window] makeKeyAndOrderFront:self];",
    )
    support = (REPO / "Tests/SourceBackspace/support.h").read_text()
    harness.write_text(support + prefix + (HERE / "probe-body.m").read_text())
    subprocess.run(
        [
            "xcrun", "clang", "-arch", "x86_64", "-mmacosx-version-min=10.13",
            "-dynamiclib", "-undefined", "dynamic_lookup", "-fno-objc-arc",
            "-Wno-deprecated-declarations", *include_flags(REPO),
            "-include", str(REPO / "Config/Notation_Prefix.pch"),
            "-framework", "Cocoa", "-framework", "Carbon", "-framework", "WebKit",
            "-o", str(dylib), str(harness),
        ],
        check=True,
    )
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
        app = root / "Native Editing Luu Round 3.app"
        shutil.copytree(APP, app, symlinks=True)
        info_path = app / "Contents/Info.plist"
        info = plistlib.loads(info_path.read_bytes())
        info["CFBundleIdentifier"] = "org.nvalt.native-editing-luu-r3." + uuid.uuid4().hex
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
        command = [str(binary), "-ShowDockIcon", "YES", "-StatusBarItem", "NO",
                   "-QuitWhenClosingMainWindow", "NO"]
        old_boolean_keys = (
            "CheckSpellingInNoteBody", "TextReplacementInNoteBody", "TabKeyIndents",
            "PastePreservesStyle", "AutoFormatsListBullets", "AutoSuggestLinks",
            "AutoIndentsNewLines", "UseSoftTabs", "UseAutoPairing",
            "UseSmartInsertDelete", "rtl",
        )
        for key in old_boolean_keys:
            command += [f"-{key}", "YES"]
        command += ["-NumberOfSpacesInTab", "17"]
        result = subprocess.run(
            command, env=environment, timeout=90,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
        )
        print(result.stdout, end="")
        marker = "LUU ROUND 3 REPRODUCED FIND REGRESSION (" in result.stdout
        if result.returncode != 0 or not marker:
            print(f"FAIL: app exited {result.returncode}; completion marker={marker}")
        return 0 if result.returncode == 0 and marker else 1


def main():
    structural_checks()
    with tempfile.TemporaryDirectory(prefix="nvalt-native-editing-luu-r3-") as temporary:
        root = Path(temporary)
        dylib = build_probe(root)
        return run_probe(root, dylib)


if __name__ == "__main__":
    raise SystemExit(main())
