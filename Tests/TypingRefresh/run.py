#!/usr/bin/env python3
"""Exercise typing refresh behavior in the actual app, with an isolated library."""
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
parser.add_argument("--compile-only", action="store_true")
parser.add_argument("--output", type=Path, default=repo / "build/TypingRefresh")
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)

with tempfile.TemporaryDirectory(prefix="nvalt-typing-refresh-") as temporary:
    root = Path(temporary)
    harness = root / "TypingRefresh.m"
    dylib = root / "TypingRefresh.dylib"
    base = (repo / "Tests/MultipleWindowsTests.m").read_text()
    prefix = base.split("- (void)nv_runTests {")[0] + "- (void)nv_runTests {"
    prefix = prefix.replace("[[self window] makeKeyAndOrderFront:self];",
                            "[NSApp activateIgnoringOtherApps:YES]; [[self window] makeKeyAndOrderFront:self];")
    prefix = prefix.replace("[self setupViewsAfterAppAwakened];", '''
    Check([[[NSBundle mainBundle] bundleIdentifier] hasPrefix:@"org.nvalt.window-tests."], @"isolated preferences domain");
    Check([[[NSBundle mainBundle] bundlePath] hasPrefix:[TestDirectory stringByAppendingString:@"/"]], @"copied app inside disposable test root");
    [self setupViewsAfterAppAwakened];''')
    suite = Path(__file__).parent
    harness.write_text((suite / "support.h").read_text() + prefix + (suite / "probe-body.m").read_text())
    subprocess.run(["xcrun", "clang", "-arch", "x86_64", "-mmacosx-version-min=10.13", "-dynamiclib",
                    "-undefined", "dynamic_lookup", "-fno-objc-arc", "-Wno-deprecated-declarations",
                    *include_flags(repo), "-include", str(repo / "Config/Notation_Prefix.pch"),
                    "-framework", "Cocoa", "-framework", "Carbon", "-framework", "WebKit",
                    "-o", str(dylib), str(harness)], check=True)
    if args.compile_only:
        print("PASS: typing-refresh native probe compiles (no app launched)")
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
        app = root / "Typing Refresh Tests.app"
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
        log_path = args.output / "native.log"
        with log_path.open("w") as log:
            process = subprocess.Popen([str(binary), "-ShowDockIcon", "YES", "-StatusBarItem", "NO",
                                        "-QuitWhenClosingMainWindow", "NO"], env=environment,
                                       stdout=log, stderr=subprocess.STDOUT)
            try:
                result = process.wait(timeout=150)
            except subprocess.TimeoutExpired:
                process.kill()
                raise SystemExit(f"Probe timed out; kill sent to disposable PID {process.pid}. Log: {log_path}")
        output = log_path.read_text()
        print(output, end="")
        full_completion = re.search(r"TYPING REFRESH PASSED \([1-9][0-9]* checks\)$", output, re.MULTILINE) is not None
        passed = result == 0 and full_completion
        report = {"app": str(args.app.resolve()), "binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
                  "mode": "production-regression",
                  "native_exit": result, "checks": len(re.findall(r"PASS: ", output)),
                  "passed": passed}
        (args.output / "results.json").write_text(json.dumps(report, indent=2) + "\n")
        print(f"{'PASS' if passed else 'FAIL'}: typing-refresh probe; report: {args.output / 'results.json'}")
        raise SystemExit(0 if passed else 1)
