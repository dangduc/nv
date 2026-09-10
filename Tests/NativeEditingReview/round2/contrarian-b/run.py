#!/usr/bin/env python3
"""Contrarian Round-2 probe for residual source-editor event policy."""
import fcntl
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import uuid

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
    editor = (REPO / "Sources/Editor/LinkingEditor.m").read_text()
    browser = (REPO / "Sources/Browser/AppController.m").read_text()
    check("- (void)flagsChanged:(NSEvent *)theEvent" in editor,
          "LinkingEditor still owns flagsChanged:")
    method = editor.split("- (void)flagsChanged:(NSEvent *)theEvent", 1)[1].split("\n}", 1)[0]
    check("[super flagsChanged:theEvent]" not in method,
          "LinkingEditor flagsChanged: does not call NSTextView")
    check("ModTimersShouldReset" in browser and "popWordCount:YES" in browser,
          "modifier interception still feeds the legacy word-count popup")
    for selector in (
        "keyDown:", "performKeyEquivalent:", "deleteBackward:", "deleteForward:",
        "insertTab:", "insertBacktab:", "insertText:",
        "selectionRangeForProposedRange:",
    ):
        stem = selector.split(":", 1)[0]
        definitions = [line for line in editor.splitlines()
                       if line.lstrip().startswith("- (") and stem in line]
        check(not definitions, f"LinkingEditor has no {selector} override")


def main():
    structural_checks()
    if not APP.is_dir():
        raise SystemExit("Build the Development app before running this review.")
    with tempfile.TemporaryDirectory(prefix="nvalt-contrarian-b-r2-") as temporary:
        root = Path(temporary)
        harness = root / "ContrarianBRound2.m"
        dylib = root / "ContrarianBRound2.dylib"
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
            "-Wno-deprecated-declarations", *include_flags(REPO), "-include",
            str(REPO / "Config/Notation_Prefix.pch"), "-framework", "Cocoa",
            "-framework", "Carbon", "-framework", "WebKit", "-o", str(dylib),
            str(harness),
        ], check=True)

        common_git = Path(subprocess.check_output(
            ["git", "rev-parse", "--git-common-dir"], cwd=REPO, text=True
        ).strip())
        if not common_git.is_absolute():
            common_git = (REPO / common_git).resolve()
        lock_path = common_git.parent / "build/pr-review/gui.lock"
        lock_path.parent.mkdir(parents=True, exist_ok=True)
        with lock_path.open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            app = root / "Contrarian B Round 2.app"
            shutil.copytree(APP, app, symlinks=True)
            info_path = app / "Contents/Info.plist"
            info = plistlib.loads(info_path.read_bytes())
            info["CFBundleIdentifier"] = "org.nvalt.contrarian-b-r2." + uuid.uuid4().hex
            info_path.write_bytes(plistlib.dumps(info))
            for directory in ("Notes", "Support", "Temp"):
                (root / directory).mkdir()
            binary = app / "Contents/MacOS" / info["CFBundleExecutable"]
            environment = dict(os.environ, NV_WINDOW_TEST_DIRECTORY=str(root),
                               DYLD_INSERT_LIBRARIES=str(dylib),
                               TMPDIR=str(root / "Temp") + "/")
            result = subprocess.run(
                [str(binary), "-ShowDockIcon", "YES", "-StatusBarItem", "NO",
                 "-QuitWhenClosingMainWindow", "NO"],
                env=environment, timeout=90, stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT, text=True,
            )
            (HERE / "output.txt").write_text(result.stdout)
            print(result.stdout, end="")
            passed = "CONTRARIAN B ROUND 2 EVIDENCE PASSED (" in result.stdout
            return 0 if result.returncode == 0 and passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
