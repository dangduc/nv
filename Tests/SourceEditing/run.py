#!/usr/bin/env python3
"""Compare source editing with a native NSTextView in the actual app."""
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

repo = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(repo / "Tests"))
from compiler_support import include_flags

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--app", type=Path, default=repo / "build/DerivedData/Build/Products/Development/nvALT.app")
parser.add_argument("--compile-only", action="store_true")
args = parser.parse_args()

locales = ("en", "de", "fr", "it", "pt-PT", "zh")
localization = repo / "Resources" / "Localization"
project = (repo / "Notation.xcodeproj" / "project.pbxproj").read_text()
for generator_name in ("NVPasswordGenerator.h", "NVPasswordGenerator.m"):
    assert not (repo / "Sources" / "Preferences" / generator_name).exists(), generator_name
    assert generator_name not in project, generator_name

removed_command_localizations = (
    "Use Automatic Text Replacement",
    "New Password...",
    "Insert New Password",
    "Insert Link",
    "Strikethrough",
)
global_prefs_h = (repo / "Sources/Preferences/GlobalPrefs.h").read_text()
global_prefs_m = (repo / "Sources/Preferences/GlobalPrefs.m").read_text()
linking_editor_h = (repo / "Sources/Editor/LinkingEditor.h").read_text()
linking_editor_m = (repo / "Sources/Editor/LinkingEditor.m").read_text()
editing_session_m = (repo / "Sources/Editor/NVNoteEditingSession.m").read_text()
app_controller_m = (repo / "Sources/Browser/AppController.m").read_text()
for removed_token in ("NumberOfSpacesInTab", "numberOfSpacesInTab",
                      "noteBodyParagraphStyle", "_bodyFontIsMonospace",
                      "setDefaultTabInterval"):
    assert removed_token not in global_prefs_h, removed_token
    assert removed_token not in global_prefs_m, removed_token
for removed_token in ("WhiteIBeamCursor", "whiteIBeamCursor", "IBeamCursorIMP",
                      "method_setImplementation", "prepareTextFinderPreLion",
                      "selectedRangeDuringFind", "stringDuringFind", "noteDuringFind",
                      "windowBecameOrResignedMain", "TextFindContextShouldNoteChanges",
                      "changedRange", "sourceSyntaxIdentifier",
                      "fixTypingAttributesForSubstitutedFonts", "lastImportedFindString",
                      "highlightRangesTemporarily", "- (void)changeColor:",
                      "- (void)didChangeText", "- (BOOL)shouldChangeTextInRange:"):
    assert removed_token not in linking_editor_h, removed_token
    assert removed_token not in linking_editor_m, removed_token
assert "TextFindContextShouldNoteChanges" not in app_controller_m
assert "textFinder = [[NSTextFinder alloc] init];" in linking_editor_m
source_change_handler = editing_session_m.split("- (void)sourceCharactersChanged:", 1)[1].split("\n}", 1)[0]
for required_token in ("editedRange", "lineRangeForRange:",
                       "removeAttribute:NSLinkAttributeName",
                       "addLinkAttributesForRange:", "sourceSyntaxIdentifier"):
    assert required_token in source_change_handler, required_token
find_handler = linking_editor_m.split("- (IBAction)performFindPanelAction:", 1)[1].split("\n}", 1)[0]
assert "generalPasteboard" not in find_handler
assert "pasteboardWithName:NSPasteboardNameFind" not in find_handler
assert "[super performTextFinderAction:newSender]" in find_handler
for locale in locales:
    root = localization / f"{locale}.lproj"
    strings_path = root / "Localizable.strings"
    subprocess.run(["plutil", "-lint", str(strings_path)], check=True,
                   stdout=subprocess.DEVNULL)
    strings = strings_path.read_text()
    for key in removed_command_localizations:
        assert f'"{key}" =' not in strings, (locale, key)
    for xib_name in ("MainMenu.xib", "BrowserWindow.xib"):
        document = ET.fromstring((root / xib_name).read_text())
        editors = [node for node in document.iter("textView")
                   if node.attrib.get("customClass") == "LinkingEditor"]
        assert len(editors) == 1, (locale, xib_name, len(editors))
        assert editors[0].attrib.get("smartInsertDelete") == "YES", (locale, xib_name)
        if xib_name == "MainMenu.xib":
            format_menus = [menu for menu in document.iter("menu")
                            if any(action.attrib.get("selector") == "fixFileEncoding:"
                                   for action in menu.iter("action"))]
            assert format_menus, locale
            for menu in format_menus:
                items = menu.find("items")
                assert items is not None and len(items), (locale, menu.attrib.get("title"))
                assert items[0].attrib.get("isSeparatorItem") != "YES", (locale, menu.attrib.get("title"))

    help_text = (root / "Excruciatingly Useful Shortcuts.nvhelp").read_text()
    for removed_token in (r"\u8592", r"\u8594", r"\u8997", "  [", "  ]"):
        assert removed_token not in help_text, (locale, removed_token)
    assert "macOS" in help_text, locale

with tempfile.TemporaryDirectory(prefix="nvalt-source-editing-") as temporary:
    root = Path(temporary)
    harness = root / "SourceEditing.m"
    dylib = root / "SourceEditing.dylib"
    base = (repo / "Tests/MultipleWindowsTests.m").read_text()
    prefix = base.split("- (void)nv_runTests {")[0] + "- (void)nv_runTests {"
    prefix = prefix.replace("[[self window] makeKeyAndOrderFront:self];",
                            "[NSApp activateIgnoringOtherApps:YES]; [[self window] makeKeyAndOrderFront:self];")
    support = (repo / "Tests/SourceBackspace/support.h").read_text()
    harness.write_text(support + prefix + Path(__file__).with_name("probe-body.m").read_text())
    subprocess.run(["xcrun", "clang", "-arch", "x86_64", "-mmacosx-version-min=10.13", "-dynamiclib",
                    "-undefined", "dynamic_lookup", "-fno-objc-arc", "-Wno-deprecated-declarations",
                    *include_flags(repo), "-include", str(repo / "Config/Notation_Prefix.pch"),
                    "-framework", "Cocoa", "-framework", "Carbon", "-framework", "WebKit",
                    "-o", str(dylib), str(harness)], check=True)
    if args.compile_only:
        print("PASS: source-editing native probe compiles")
        raise SystemExit(0)
    if not args.app.is_dir():
        raise SystemExit("Build the Development app or supply --app.")
    common_git = Path(subprocess.check_output(["git", "rev-parse", "--git-common-dir"], cwd=repo, text=True).strip())
    if not common_git.is_absolute():
        common_git = (repo / common_git).resolve()
    lock_path = common_git.parent / "build/pr-review/gui.lock"
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    with lock_path.open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        app = root / "Source Editing Tests.app"
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
        result = subprocess.run([str(binary), "-ShowDockIcon", "YES", "-StatusBarItem", "NO",
                                 "-QuitWhenClosingMainWindow", "NO"], env=environment, timeout=90,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        print(result.stdout, end="")
        completed = "SOURCE EDITING PASSED (" in result.stdout
        if result.returncode != 0 or not completed:
            print(f"FAIL: source-editing app exited {result.returncode} without its completion marker")
        raise SystemExit(0 if result.returncode == 0 and completed else 1)
