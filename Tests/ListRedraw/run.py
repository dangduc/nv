#!/usr/bin/env python3
"""Check repeated notes-list drawing in a copied app with disposable notes."""
import argparse
import fcntl
import hashlib
import json
import re
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import uuid

repo = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(repo / "Tests"))
from compiler_support import include_flags

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--app", type=Path, default=repo / "build/DerivedData/Build/Products/Development/nvALT Development.app")
parser.add_argument("--label", default="candidate")
parser.add_argument("--negative-control", action="store_true", help="restore the false opacity declaration and require pixel drift")
args = parser.parse_args()
output = repo / "build/ListRedrawFix" / args.label
output.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix="disposable-", dir=output) as temporary:
    root = Path(temporary)
    source = root / "ListRedraw.m"
    library = root / "ListRedraw.dylib"
    prefix = (repo / "Tests/MultipleWindowsTests.m").read_text().split("- (void)nv_runTests {")[0]
    prefix = prefix.replace("[[self window] makeKeyAndOrderFront:self];",
        "[NSApp activateIgnoringOtherApps:YES]; [[self window] makeKeyAndOrderFront:self];")
    suite = Path(__file__).parent
    source.write_text((suite / "app-support.h").read_text() + prefix + "- (void)nv_runTests {" +
        (suite / "app-body.m").read_text())
    subprocess.run(["xcrun", "clang", "-arch", "x86_64", "-mmacosx-version-min=10.13", "-dynamiclib",
        "-undefined", "dynamic_lookup", "-fno-objc-arc", "-Wno-deprecated-declarations", *include_flags(repo),
        "-include", str(repo / "Config/Notation_Prefix.pch"), "-framework", "Cocoa", "-framework", "Carbon",
        "-framework", "WebKit", "-o", str(library), str(source)], check=True)
    common = Path(subprocess.check_output(["git", "rev-parse", "--git-common-dir"], cwd=repo, text=True).strip())
    if not common.is_absolute():
        common = (repo / common).resolve()
    lock_path = common.parent / "build/pr-review/gui.lock"
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    with lock_path.open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        app = root / "List Redraw Tests.app"
        shutil.copytree(args.app, app, symlinks=True)
        info_path = app / "Contents/Info.plist"
        info = plistlib.loads(info_path.read_bytes())
        info["CFBundleIdentifier"] = "org.nvalt.window-tests." + uuid.uuid4().hex
        info_path.write_bytes(plistlib.dumps(info))
        for name in ("Notes", "Support", "Temp"):
            (root / name).mkdir()
        environment = dict(os.environ, NV_WINDOW_TEST_DIRECTORY=str(root), DYLD_INSERT_LIBRARIES=str(library),
            TMPDIR=str(root / "Temp") + "/")
        environment["NV_REVIEW_CAPTURE"] = str(output / "list-redraw.png")
        if args.negative_control:
            environment["NV_LIST_OPAQUE_NEGATIVE"] = "1"
        binary_hash = hashlib.sha256((app / "Contents/MacOS" / info["CFBundleExecutable"]).read_bytes()).hexdigest()
        result = subprocess.run([str(app / "Contents/MacOS" / info["CFBundleExecutable"]), "-ShowDockIcon", "YES",
            "-StatusBarItem", "NO", "-QuitWhenClosingMainWindow", "NO"], env=environment,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=120)
        (output / f"{args.label}.log").write_text(result.stdout)
        result_record = {"app_sha256": binary_hash, "exit_code": result.returncode,
            "checks": len(re.findall(r"PASS:", result.stdout)),
            "passed": "LIST REDRAW TESTS PASSED (" in result.stdout,
            "failure": re.findall(r"FAIL: (.*)", result.stdout)}
        (output / f"{args.label}.json").write_text(json.dumps(result_record, indent=2) + "\n")
        print(result.stdout, end="")
        if args.negative_control:
            expected = result.returncode != 0 and "FAIL: repeated redraw preserves every captured pixel" in result.stdout
            print("PASS: false opacity causes pixel drift" if expected else "FAIL: negative control did not expose pixel drift")
            raise SystemExit(0 if expected else 1)
        raise SystemExit(0 if result.returncode == 0 and "LIST REDRAW TESTS PASSED (" in result.stdout else 1)
