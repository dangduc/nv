#!/usr/bin/env python3
"""Run lifecycle cleanup histories in a copied production nvALT app."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import uuid

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
sys.path.insert(0, str(REPO / "Tests"))
from compiler_support import include_flags

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--app", type=Path, default=REPO / "build/DerivedData/Build/Products/Development/nvALT.app")
parser.add_argument("--compile-only", action="store_true")
args = parser.parse_args()
paths = ["Sources/Editor/NVSourceTypesetter.m", "Sources/Editor/NVSourceTypesetter.h",
         "Sources/Editor/LinkingEditor.m", "Sources/Editor/NVNoteEditingSession.m"]
hashes = lambda: {p: hashlib.sha256((REPO / p).read_bytes()).hexdigest() for p in paths}
before = hashes()
head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=REPO, text=True).strip()
with tempfile.TemporaryDirectory(prefix="nvalt-wrap-lifecycle-") as temporary:
    root = Path(temporary)
    source = root / "History.m"
    dylib = root / "History.dylib"
    prefix = (REPO / "Tests/MultipleWindowsTests.m").read_text().split("- (void)nv_runTests {")[0]
    prefix = prefix.replace("[[self window] makeKeyAndOrderFront:self];",
                            "[NSApp activateIgnoringOtherApps:YES]; [[self window] makeKeyAndOrderFront:self];")
    source.write_text(prefix + (HERE / "probe-support.h").read_text() + "- (void)nv_runTests {" +
                      (HERE / "probe-body.m").read_text())
    compile_result = subprocess.run(["xcrun", "clang", "-arch", "x86_64", "-mmacosx-version-min=10.13",
        "-dynamiclib", "-undefined", "dynamic_lookup", "-fno-objc-arc", "-Wno-deprecated-declarations",
        *include_flags(REPO), "-include", str(REPO / "Config/Notation_Prefix.pch"), "-framework", "Cocoa",
        "-framework", "Carbon", "-framework", "WebKit", "-o", str(dylib), str(source)],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (HERE / "compile.log").write_text(compile_result.stdout)
    if compile_result.returncode:
        print(compile_result.stdout)
        raise SystemExit(compile_result.returncode)
    if args.compile_only:
        print("PASS: history checks compile; no application started")
        raise SystemExit(0)
    common = Path(subprocess.check_output(["git", "rev-parse", "--git-common-dir"], cwd=REPO, text=True).strip())
    if not common.is_absolute():
        common = (REPO / common).resolve()
    lock_path = common.parent / "build/pr-review/gui.lock"
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    with lock_path.open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        app = root / "Layout Lifecycle Tests.app"
        shutil.copytree(args.app, app, symlinks=True)
        info_path = app / "Contents/Info.plist"
        info = plistlib.loads(info_path.read_bytes())
        info["CFBundleIdentifier"] = "org.nvalt.window-tests." + uuid.uuid4().hex
        info_path.write_bytes(plistlib.dumps(info))
        for name in ("Notes", "Support", "Temp"):
            (root / name).mkdir()
        environment = dict(os.environ, NV_WINDOW_TEST_DIRECTORY=str(root), DYLD_INSERT_LIBRARIES=str(dylib),
                           NV_HISTORY_RESULT=str(HERE / "observations.json"), TMPDIR=str(root / "Temp") + "/")
        executable = app / "Contents/MacOS" / info["CFBundleExecutable"]
        binary_hash = hashlib.sha256(executable.read_bytes()).hexdigest()
        result = subprocess.run([str(executable), "-ShowDockIcon", "YES", "-StatusBarItem", "NO",
            "-QuitWhenClosingMainWindow", "NO"], env=environment, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, text=True, timeout=120)
        (HERE / "app.log").write_text(result.stdout)
    after = hashes()
    passed = result.returncode == 0 and "LIFECYCLE REVIEW PASSED (" in result.stdout
    record = {"reviewed_head": head, "app_sha256": binary_hash, "exit_code": result.returncode,
        "passed": passed, "checks": len(re.findall(r"PASS:", result.stdout)),
        "failures": re.findall(r"FAIL: (.*)", result.stdout), "source_hashes_before": before,
        "source_hashes_after": after, "production_unchanged": before == after,
        "platform": subprocess.check_output(["sw_vers"], text=True).strip(),
        "xcode": subprocess.check_output(["xcodebuild", "-version"], text=True).strip(),
        "gui_lock": str(lock_path), "architecture": "x86_64 through Rosetta"}
    (HERE / "results.json").write_text(json.dumps(record, indent=2) + "\n")
    print(result.stdout, end="")
    raise SystemExit(0 if passed and before == after else 1)
