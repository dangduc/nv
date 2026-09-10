#!/usr/bin/env python3
"""Reproduce the source editor's remaining note-title completion provider."""
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


with tempfile.TemporaryDirectory(prefix="nvalt-native-editing-luu-r1-") as temporary:
    root = Path(temporary)
    harness = root / "NativeEditingLuuR1.m"
    dylib = root / "NativeEditingLuuR1.dylib"
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
        raise SystemExit("Build the Development app before running this probe.")

    common_git = Path(subprocess.check_output(
        ["git", "rev-parse", "--git-common-dir"], cwd=REPO, text=True
    ).strip())
    if not common_git.is_absolute():
        common_git = (REPO / common_git).resolve()
    lock_path = common_git.parent / "build/pr-review/gui.lock"
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    with lock_path.open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        app = root / "Native Editing Luu Round 1.app"
        shutil.copytree(APP, app, symlinks=True)
        info_path = app / "Contents/Info.plist"
        info = plistlib.loads(info_path.read_bytes())
        info["CFBundleIdentifier"] = "org.nvalt.native-editing-review." + uuid.uuid4().hex
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
            env=environment,
            timeout=90,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        print(result.stdout, end="")
        reproduced = "LUU NATIVE EDITING REVIEW REPRODUCED (" in result.stdout
        raise SystemExit(0 if result.returncode == 0 and reproduced else 1)
