#!/usr/bin/env python3
"""Compare native IME/Undo/lifecycle histories in copied candidate and base apps."""
import fcntl
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import uuid

here = Path(__file__).resolve().parent
repo = here.parents[3]
sys.path.insert(0, str(repo / "Tests"))
from compiler_support import include_flags

out = repo / "build/WhitespaceWrapReview/round1/kingsbury"
out.mkdir(parents=True, exist_ok=True)
prefix = (repo / "Tests/MultipleWindowsTests.m").read_text().split("- (void)nv_runTests {")[0]
prefix = prefix.replace("[[self window] makeKeyAndOrderFront:self];",
                        "[NSApp activateIgnoringOtherApps:YES]; [[self window] makeKeyAndOrderFront:self];")
generated = out / "probe.m"
generated.write_text((here / "support.h").read_text() + prefix + "- (void)nv_runTests {" +
                     (here / "body.m").read_text())
library = out / "probe.dylib"
subprocess.run(["xcrun", "clang", "-arch", "x86_64", "-mmacosx-version-min=10.13", "-dynamiclib",
               "-undefined", "dynamic_lookup", "-fno-objc-arc", "-Wno-deprecated-declarations",
               *include_flags(repo), "-include", str(repo / "Config/Notation_Prefix.pch"),
               "-framework", "Cocoa", "-framework", "Carbon", "-framework", "WebKit",
               "-o", str(library), str(generated)], check=True)
apps = {
    "candidate": repo / "build/DerivedData/Build/Products/Development/nvALT.app",
    "baseline": Path("/Users/duc/dev/nv/build/TypingPerformanceWorktree/build/DerivedData/Build/Products/Development/nvALT.app"),
}
lock_path = Path("/Users/duc/dev/nv/build/pr-review/gui.lock")
lock_path.parent.mkdir(parents=True, exist_ok=True)
results = {}
with lock_path.open("a") as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    for mode, original in apps.items():
        with tempfile.TemporaryDirectory(prefix="nvalt-wrap-ime-") as temporary:
            root = Path(temporary)
            app = root / "IME Review.app"
            shutil.copytree(original, app, symlinks=True)
            info_path = app / "Contents/Info.plist"
            info = plistlib.loads(info_path.read_bytes())
            info["CFBundleIdentifier"] = "org.nvalt.window-tests." + uuid.uuid4().hex
            info_path.write_bytes(plistlib.dumps(info))
            for name in ("Notes", "Support", "Temp"):
                (root / name).mkdir()
            result_path = out / (mode + ".json")
            env = dict(os.environ, NV_WINDOW_TEST_DIRECTORY=str(root), DYLD_INSERT_LIBRARIES=str(library),
                       NV_WRAP_REVIEW_MODE=mode, NV_WRAP_REVIEW_OUTPUT=str(result_path), TMPDIR=str(root / "Temp") + "/")
            completed = subprocess.run([str(app / "Contents/MacOS" / info["CFBundleExecutable"]),
                "-ShowDockIcon", "YES", "-StatusBarItem", "NO", "-QuitWhenClosingMainWindow", "NO"],
                env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=180)
            (out / (mode + ".log")).write_text(completed.stdout)
            print(mode, completed.returncode, completed.stdout[-2200:])
            assert completed.returncode == 0 and "WRAP IME REVIEW PASSED" in completed.stdout
            results[mode] = json.loads(result_path.read_text())
assert results["candidate"]["history"] == results["baseline"]["history"], "candidate/base state history differs"
assert results["candidate"]["markedGlyphCallbacks"] > 0
assert results["candidate"]["wrapLines"] > 1
assert results["baseline"]["wrapLines"] == 1
(here / "results.json").write_text(json.dumps(results, indent=2) + "\n")
print("PASS: candidate/base state histories agree; wrapping differs as expected; real glyph callbacks ran during marked text")
