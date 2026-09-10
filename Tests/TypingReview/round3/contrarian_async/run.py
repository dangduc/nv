#!/usr/bin/env python3
"""Exercise actual source-analysis wiring in the actual app, with an isolated library."""
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

repo = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(repo / "Tests"))
from compiler_support import include_flags

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--app", type=Path, default=repo / "build/DerivedData/Build/Products/Development/nvALT.app")
parser.add_argument("--compile-only", action="store_true")
parser.add_argument("--output", type=Path, default=repo / "build/TypingReview/round3/contrarian_async")
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)

with tempfile.TemporaryDirectory(prefix="nvalt-typing-async-") as temporary:
    root = Path(temporary)
    harness = root / "TypingAsync.m"
    dylib = root / "TypingAsync.dylib"
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
        print("PASS: typing-async native probe compiles (no app launched)")
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
        app = root / "Typing Async Tests.app"
        shutil.copytree(args.app, app, symlinks=True)
        info_path = app / "Contents/Info.plist"
        info = plistlib.loads(info_path.read_bytes())
        info["CFBundleIdentifier"] = "org.nvalt.window-tests." + uuid.uuid4().hex
        info_path.write_bytes(plistlib.dumps(info))
        for directory in ("Notes", "Support", "Temp"):
            (root / directory).mkdir()
        binary = app / "Contents/MacOS" / info["CFBundleExecutable"]
        symbols = []
        for line in subprocess.check_output(["nm", "-n", str(binary)], text=True).splitlines():
            fields = line.split(maxsplit=2)
            if len(fields) == 3:
                try: symbols.append((int(fields[0], 16), fields[2]))
                except ValueError: pass
        helper_sizes = {}
        for name in ("_NVSourceWordCount", "_NVSourceLinkRuns"):
            index = next(i for i, entry in enumerate(symbols) if entry[1] == name)
            helper_sizes[name] = symbols[index+1][0] - symbols[index][0]
        worker_index = next(i for i, entry in enumerate(symbols) if entry[1] == "___25-[NVSourceAnalysis start]_block_invoke_2")
        word_address = next(entry[0] for entry in symbols if entry[1] == "_NVSourceWordCount")
        worker_offset = symbols[worker_index][0] - word_address
        worker_size = symbols[worker_index+1][0] - symbols[worker_index][0]
        environment = dict(os.environ, NV_WORKER_OFFSET=str(worker_offset), NV_WORKER_SIZE=str(worker_size), NV_WORD_HELPER_SIZE=str(helper_sizes["_NVSourceWordCount"]), NV_LINK_HELPER_SIZE=str(helper_sizes["_NVSourceLinkRuns"]), NV_WINDOW_TEST_DIRECTORY=str(root),
                           DYLD_INSERT_LIBRARIES=str(dylib), TMPDIR=str(root / "Temp") + "/", NV_ASYNC_OBSERVATIONS=str((args.output / "observations.json").resolve()))
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
        (suite / "output.txt").write_text(output)
        print(output, end="")
        full_completion = re.search(r"TYPING ASYNC PASSED \([1-9][0-9]* checks\)$", output, re.MULTILINE) is not None
        passed = result == 0 and full_completion
        report = {"app": str(args.app.resolve()), "binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
                  "mode": "production-regression",
                  "head": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip(),
                  "helper_symbol_sizes": helper_sizes, "worker_offset_from_word_helper": worker_offset, "worker_symbol_size": worker_size,
                  "native_exit": result, "checks": len(re.findall(r"PASS: ", output)),
                  "passed": passed}
        (args.output / "results.json").write_text(json.dumps(report, indent=2) + "\n")
        (suite / "results.json").write_text(json.dumps(report, indent=2) + "\n")
        print(f"{'PASS' if passed else 'FAIL'}: typing-async probe; report: {args.output / 'results.json'}")
        raise SystemExit(0 if passed else 1)
