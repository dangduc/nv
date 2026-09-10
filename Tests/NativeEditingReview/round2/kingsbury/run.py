#!/usr/bin/env python3
"""Stress shared source editing while layouts, responders, and workers change."""
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

repo = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(repo / "Tests"))
from compiler_support import include_flags

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--app", type=Path,
                    default=repo / "build/DerivedData/Build/Products/Development/nvALT.app")
parser.add_argument("--compile-only", action="store_true")
args = parser.parse_args()

with tempfile.TemporaryDirectory(prefix="nvalt-native-r2-kingsbury-") as temporary:
    root = Path(temporary)
    harness = root / "NativeEditingKingsbury.m"
    dylib = root / "NativeEditingKingsbury.dylib"
    base = (repo / "Tests/MultipleWindowsTests.m").read_text()
    prefix = base.split("- (void)nv_runTests {")[0] + "- (void)nv_runTests {"
    prefix = prefix.replace("[[self window] makeKeyAndOrderFront:self];",
                            "[NSApp activateIgnoringOtherApps:YES]; [[self window] makeKeyAndOrderFront:self];")
    support = (repo / "Tests/SourceBackspace/support.h").read_text()
    harness.write_text(support + prefix + Path(__file__).with_name("probe-body.m").read_text())
    subprocess.run([
        "xcrun", "clang", "-arch", "x86_64", "-mmacosx-version-min=10.13",
        "-dynamiclib", "-undefined", "dynamic_lookup", "-fno-objc-arc",
        "-Wno-deprecated-declarations", *include_flags(repo),
        "-include", str(repo / "Config/Notation_Prefix.pch"),
        "-framework", "Cocoa", "-framework", "Carbon", "-framework", "WebKit",
        "-o", str(dylib), str(harness),
    ], check=True)
    if args.compile_only:
        print("PASS: round-2 Kingsbury native-editing probe compiles")
        raise SystemExit(0)
    if not args.app.is_dir():
        raise SystemExit("Build the Development app or supply --app.")
    common_git = Path(subprocess.check_output(
        ["git", "rev-parse", "--git-common-dir"], cwd=repo, text=True).strip())
    if not common_git.is_absolute():
        common_git = (repo / common_git).resolve()
    lock_path = common_git.parent / "build/pr-review/gui.lock"
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    with lock_path.open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        app = root / "Native Editing Kingsbury Round 2.app"
        shutil.copytree(args.app, app, symlinks=True)
        info_path = app / "Contents/Info.plist"
        info = plistlib.loads(info_path.read_bytes())
        info["CFBundleIdentifier"] = "org.nvalt.native-review." + uuid.uuid4().hex
        info_path.write_bytes(plistlib.dumps(info))
        for directory in ("Notes", "Support", "Temp"):
            (root / directory).mkdir()
        binary = app / "Contents/MacOS" / info["CFBundleExecutable"]
        environment = dict(os.environ, NV_WINDOW_TEST_DIRECTORY=str(root),
                           DYLD_INSERT_LIBRARIES=str(dylib), TMPDIR=str(root / "Temp") + "/")
        result = subprocess.run([
            str(binary), "-ShowDockIcon", "YES", "-StatusBarItem", "NO",
            "-QuitWhenClosingMainWindow", "NO",
        ], env=environment, timeout=120, stdout=subprocess.PIPE,
           stderr=subprocess.STDOUT, text=True)
        print(result.stdout, end="")
        completed = "KINGSBURY ROUND 2 PASSED (" in result.stdout
        if not completed:
            print(f"probe process exited {result.returncode} without its completion marker")
        raise SystemExit(0 if result.returncode == 0 and completed else 1)
