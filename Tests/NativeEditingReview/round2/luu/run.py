#!/usr/bin/env python3
"""Probe native source-editing defaults and edge behavior after round-one fixes."""
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
    source = "\n".join(
        path.read_text(errors="ignore")
        for path in (REPO / "Sources").rglob("*")
        if path.suffix in {".h", ".m", ".c", ".mm"}
    )
    retired = (
        "CheckSpellingInNoteBody", "TabKeyIndents", "AutoSuggestLinks",
        "UseSoftTabs", "SoftTabsSpaces", "UseAutoPairing",
        "changedTabBehavior:", "changedSpellChecking:",
        "changedAutoSuggestLinks:", "changedSoftTabs:",
        "changedAutoPairing:", "changedRTL:", "pasteMarkdownLink:",
        "shiftLeftAction:", "shiftRightAction:", "strikethroughNV:",
    )
    for token in retired:
        check(token not in source, f"production source omits retired behavior {token}")

    localization = REPO / "Resources/Localization"
    for locale in ("en", "de", "fr", "it", "pt-PT", "zh"):
        root = localization / f"{locale}.lproj"
        for name in ("MainMenu.xib", "BrowserWindow.xib", "Preferences.xib"):
            path = root / name
            document = ET.parse(path)
            check(document.getroot() is not None, f"{locale} {name} parses")
            if name in ("MainMenu.xib", "BrowserWindow.xib"):
                editors = [node for node in document.iter("textView")
                           if node.attrib.get("customClass") == "LinkingEditor"]
                check(len(editors) == 1, f"{locale} {name} has one source editor")
                check(editors[0].attrib.get("smartInsertDelete") == "YES",
                      f"{locale} {name} enables native Smart Copy/Paste default")
            if name == "MainMenu.xib":
                actions = [node.attrib.get("selector") for node in document.iter("action")]
                for selector in (
                    "toggleContinuousSpellChecking:", "toggleSmartInsertDelete:",
                    "toggleAutomaticQuoteSubstitution:",
                    "toggleAutomaticDashSubstitution:",
                    "toggleAutomaticTextReplacement:",
                ):
                    check(selector in actions, f"{locale} menu routes {selector} to first responder")
                format_menus = [menu for menu in document.iter("menu")
                                if [action.attrib.get("selector") for action in menu.iter("action")]
                                == ["fixFileEncoding:"]]
                check(len(format_menus) == 2, f"{locale} has main and status Format menus")
                for menu in format_menus:
                    items = menu.find("items")
                    check(items is not None and len(items) and
                          items[0].attrib.get("isSeparatorItem") != "YES",
                          f"{locale} Format menu starts with a command")

        rendered = subprocess.run(
            ["textutil", "-convert", "txt", "-stdout",
             str(root / "Excruciatingly Useful Shortcuts.nvhelp")],
            check=True, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        ).stdout
        check("macOS" in rendered, f"{locale} help RTF decodes with native-editing guidance")


def main():
    structural_checks()
    with tempfile.TemporaryDirectory(prefix="nvalt-native-editing-luu-r2-") as temporary:
        root = Path(temporary)
        harness = root / "NativeEditingLuuR2.m"
        dylib = root / "NativeEditingLuuR2.dylib"
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
            app = root / "Native Editing Luu Round 2.app"
            shutil.copytree(APP, app, symlinks=True)
            info_path = app / "Contents/Info.plist"
            info = plistlib.loads(info_path.read_bytes())
            info["CFBundleIdentifier"] = "org.nvalt.native-editing-luu-r2." + uuid.uuid4().hex
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
            for key in ("CheckSpellingInNoteBody", "TabKeyIndents", "AutoSuggestLinks",
                        "UseSoftTabs", "UseAutoPairing", "rtl"):
                command += [f"-{key}", "YES"]
            result = subprocess.run(
                command, env=environment, timeout=90,
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
            )
            print(result.stdout, end="")
            passed = "LUU ROUND 2 PASSED (" in result.stdout
            return 0 if result.returncode == 0 and passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
