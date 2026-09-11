#!/usr/bin/env python3
"""Check wrapped source separators in a copied nvALT app with disposable notes."""
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

repo = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(repo / "Tests"))
from compiler_support import include_flags

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--app", type=Path, default=repo / "build/DerivedData/Build/Products/Development/nvALT Development.app")
parser.add_argument("--output", type=Path, default=repo / "build/WrappedSeparatorsApp")
parser.add_argument("--compile-only", action="store_true", help="compile the injected checks without launching an app")
args = parser.parse_args()

with tempfile.TemporaryDirectory(prefix="nvalt-wrapped-separators-") as temporary:
    root = Path(temporary)
    source = root / "WrappedSeparators.m"
    library = root / "WrappedSeparators.dylib"
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
    if args.compile_only:
        print("PASS: copied-app wrapped-separators checks compile; no app was launched")
        raise SystemExit(0)

    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    common = Path(subprocess.check_output(["git", "rev-parse", "--git-common-dir"], cwd=repo, text=True).strip())
    if not common.is_absolute():
        common = (repo / common).resolve()
    lock_path = common.parent / "build/pr-review/gui.lock"
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    with lock_path.open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        app = root / "Wrapped Separators Tests.app"
        shutil.copytree(args.app, app, symlinks=True)
        info_path = app / "Contents/Info.plist"
        info = plistlib.loads(info_path.read_bytes())
        info["CFBundleIdentifier"] = "org.nvalt.window-tests." + uuid.uuid4().hex
        info_path.write_bytes(plistlib.dumps(info))
        for name in ("Notes", "Support", "Temp"):
            (root / name).mkdir()
        environment = dict(os.environ, NV_WINDOW_TEST_DIRECTORY=str(root), DYLD_INSERT_LIBRARIES=str(library),
            NV_SEPARATOR_CAPTURE=str(output / "wrapped-separators.png"), NV_SEPARATOR_RESULT=str(output / "observations.json"),
            TMPDIR=str(root / "Temp") + "/")
        executable = app / "Contents/MacOS" / info["CFBundleExecutable"]
        binary_hash = hashlib.sha256(executable.read_bytes()).hexdigest()
        result = subprocess.run([str(executable), "-ShowDockIcon", "YES", "-StatusBarItem", "NO",
            "-QuitWhenClosingMainWindow", "NO"], env=environment, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, text=True, timeout=120)
        (output / "app.log").write_text(result.stdout)
        passed = result.returncode == 0 and "WRAPPED SEPARATORS APP PASSED (" in result.stdout
        record = {"app_sha256":binary_hash,"exit_code":result.returncode,"passed":passed,
            "checks":len(re.findall(r"PASS:",result.stdout)),"failures":re.findall(r"FAIL: (.*)",result.stdout)}
        (output / "result.json").write_text(json.dumps(record,indent=2) + "\n")
        print(result.stdout,end="")
        raise SystemExit(0 if passed else 1)
