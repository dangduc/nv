#!/usr/bin/env python3
"""Audit localized UI and exercise native NSTextView boundaries in nvALT."""
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

repo = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(repo / "Tests"))
from compiler_support import include_flags

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--app", type=Path, default=repo / "build/DerivedData/Build/Products/Development/nvALT.app")
parser.add_argument("--static-only", action="store_true")
args = parser.parse_args()

locales = ("en", "de", "fr", "it", "pt-PT", "zh")
removed_preferences = {
    "changedAutoPairing:", "changedAutoSuggestLinks:", "changedSpellChecking:",
    "changedSoftTabs:", "changedStyledTextBehavior:", "changedTabBehavior:", "changedRTL:",
}
removed_menu_actions = {
    "pasteMarkdownLink:", "strikethroughNV:", "bold:", "italic:",
    "shiftLeftAction:", "shiftRightAction:", "insertLink:",
}
native_menu_actions = {
    "toggleContinuousSpellChecking:", "toggleSmartInsertDelete:",
    "toggleAutomaticQuoteSubstitution:", "toggleAutomaticDashSubstitution:",
    "toggleAutomaticTextReplacement:",
}
legacy_tokens = {
    "CheckSpellingInNoteBody", "TabKeyIndents", "AutoSuggestLinks", "UseSoftTabs",
    "UseAutoPairing", "AutoFormatsListBullets", "AutoIndentsNewLines", 'key="rtl"',
}

checks = 0
for locale in locales:
    root = repo / "Resources" / "Localization" / f"{locale}.lproj"
    preferences_text = (root / "Preferences.xib").read_text()
    menu_text = (root / "MainMenu.xib").read_text()
    ET.fromstring(preferences_text)
    ET.fromstring(menu_text)
    assert not any(token in preferences_text for token in removed_preferences), locale
    assert not any(token in menu_text for token in removed_menu_actions), locale
    for action in native_menu_actions:
        assert menu_text.count(f'selector="{action}" target="-1"') == 1, (locale, action)
    for xib_name in ("MainMenu.xib", "BrowserWindow.xib"):
        xib_text = (root / xib_name).read_text()
        editor_nodes = [node for node in ET.fromstring(xib_text).iter("textView")
                        if node.attrib.get("customClass") == "LinkingEditor"]
        assert len(editor_nodes) == 1, (locale, xib_name, len(editor_nodes))
        node = editor_nodes[0]
        assert node.attrib.get("richText") == "NO" and node.attrib.get("importsGraphics") == "NO"
        # NSTextView's fresh runtime default is automatic spelling correction enabled.
        assert node.attrib.get("spellingCorrection") == "YES"
    checks += 1

production = "\n".join(
    path.read_text(errors="replace")
    for directory in (repo / "Sources", repo / "Config")
    for path in directory.rglob("*") if path.is_file()
)
for token in legacy_tokens:
    assert token not in production, token
checks += 1

for locale in locales:
    for xib_name in ("Preferences.xib", "MainMenu.xib"):
        with tempfile.TemporaryDirectory(prefix="nvalt-review-xib-") as temporary:
            subprocess.run(["xcrun", "ibtool", "--compile", str(Path(temporary) / "output.nib"),
                            str(repo / "Resources" / "Localization" / f"{locale}.lproj" / xib_name)],
                           check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
checks += 1
print(f"PASS: localized/static native editing audit ({checks} checks)")

if args.static_only:
    raise SystemExit(0)
if not args.app.is_dir():
    raise SystemExit("Build the Development app or supply --app.")

with tempfile.TemporaryDirectory(prefix="nvalt-contrarian-native-") as temporary:
    root = Path(temporary)
    harness = root / "ContrarianNativeBoundary.m"
    dylib = root / "ContrarianNativeBoundary.dylib"
    base = (repo / "Tests" / "MultipleWindowsTests.m").read_text()
    prefix = base.split("- (void)nv_runTests {")[0] + "- (void)nv_runTests {"
    prefix = prefix.replace("[[self window] makeKeyAndOrderFront:self];",
                            "[NSApp activateIgnoringOtherApps:YES]; [[self window] makeKeyAndOrderFront:self];")
    support = (repo / "Tests" / "SourceBackspace" / "support.h").read_text()
    harness.write_text(support + prefix + Path(__file__).with_name("probe-body.m").read_text())
    subprocess.run(["xcrun", "clang", "-arch", "x86_64", "-mmacosx-version-min=10.13", "-dynamiclib",
                    "-undefined", "dynamic_lookup", "-fno-objc-arc", "-Wno-deprecated-declarations",
                    *include_flags(repo), "-include", str(repo / "Config" / "Notation_Prefix.pch"),
                    "-framework", "Cocoa", "-framework", "Carbon", "-framework", "WebKit",
                    "-o", str(dylib), str(harness)], check=True)
    common_git = Path(subprocess.check_output(["git", "rev-parse", "--git-common-dir"], cwd=repo, text=True).strip())
    if not common_git.is_absolute():
        common_git = (repo / common_git).resolve()
    lock_path = common_git.parent / "build/pr-review/gui.lock"
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    with lock_path.open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        app = root / "Contrarian Native Boundary.app"
        shutil.copytree(args.app, app, symlinks=True)
        info_path = app / "Contents" / "Info.plist"
        info = plistlib.loads(info_path.read_bytes())
        info["CFBundleIdentifier"] = "org.nvalt.window-tests." + uuid.uuid4().hex
        info_path.write_bytes(plistlib.dumps(info))
        for directory in ("Notes", "Support", "Temp"):
            (root / directory).mkdir()
        binary = app / "Contents" / "MacOS" / info["CFBundleExecutable"]
        environment = dict(os.environ, NV_WINDOW_TEST_DIRECTORY=str(root),
                           DYLD_INSERT_LIBRARIES=str(dylib), TMPDIR=str(root / "Temp") + "/")
        result = subprocess.run([str(binary), "-ShowDockIcon", "YES", "-StatusBarItem", "NO",
                                 "-QuitWhenClosingMainWindow", "NO"], env=environment, timeout=90,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        print(result.stdout, end="")
        completed = "CONTRARIAN NATIVE BOUNDARY PASSED (" in result.stdout
        raise SystemExit(0 if result.returncode == 0 and completed else result.returncode or 1)
