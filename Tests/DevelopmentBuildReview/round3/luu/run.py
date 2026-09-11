#!/usr/bin/env python3
"""Frozen backup namespace cost and worker ownership; disposable paths, no GUI."""
from pathlib import Path
import json
import plistlib
import re
import shutil
import statistics
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
COMMIT = "47d18f4"


def source(path):
    return subprocess.check_output(["git", "show", f"{COMMIT}:{path}"], cwd=ROOT, text=True)


def method(text, signature):
    start = text.index(signature)
    end = re.search(r"\n[+-] \(", text[start + len(signature):])
    assert end
    return text[start:start + len(signature) + end.start()]


controller = source("Sources/Storage/NVBackupController.m")
store = source("Sources/Storage/NVBackupStore.m")
assert "[worker setMaxConcurrentOperationCount:1]" in controller
assert "[worker setQualityOfService:NSQualityOfServiceUtility]" in controller
helpers = controller[controller.index("static NSError *BackupError"):controller.index("static NSString *DateLabel")]
start = controller.index("static BOOL ValidBackupPath")
helpers += controller[start:controller.index("static NSDictionary *ValidatedSavedBackupSettings", start)]
methods = "\n".join(method(controller, signature) for signature in ["- (NSURL *)rootURLWithError:", "- (NSURL *)checkedDestinationWithError:", "- (void)beginBackupAtDate:"])
store_helpers = store[store.index("static BOOL NVError("):store.index("static BOOL NVUUID(")]
opening = store[store.index("static int NVOpenDirectory("):store.index("static BOOL NVSync(")]
probe = (HERE / "probe.m").read_text()
for key, value in {"@IDENTITY@": source("Sources/Application/NVAppIdentity.h"), "@CONTROLLER_HELPERS@": helpers, "@CONTROLLER_METHODS@": methods, "@STORE_HELPERS@": store_helpers, "@OPENING@": opening}.items():
    probe = probe.replace(key, value)
assert not re.search(r"@[A-Z_]+@", probe)
report = {"commit": subprocess.check_output(["git", "rev-parse", COMMIT], cwd=ROOT, text=True).strip(), "environment": subprocess.check_output(["sw_vers"], text=True).strip(), "xcode": subprocess.check_output(["xcodebuild", "-version"], text=True).strip(), "architecture": "x86_64 through Rosetta on arm64"}
with tempfile.TemporaryDirectory(prefix="probe-", dir=HERE) as temporary:
    temp = Path(temporary).resolve()
    (temp / "probe.m").write_text(probe)
    binary = temp / "probe"
    build = subprocess.run(["xcrun", "clang", "-arch", "x86_64", "-O2", "-fno-objc-arc", "-fblocks", "-Wno-deprecated-declarations", "-framework", "Cocoa", str(temp / "probe.m"), "-o", str(binary)], capture_output=True, text=True, timeout=60)
    (HERE / "compile.log").write_text(build.stdout + build.stderr)
    build.check_returncode()
    app = temp / "development.app"
    executable = app / "Contents/MacOS/probe"
    executable.parent.mkdir(parents=True)
    shutil.copy2(binary, executable)
    (app / "Contents/Info.plist").write_bytes(plistlib.dumps({"CFBundleExecutable": "probe", "CFBundlePackageType": "APPL", "CFBundleIdentifier": "org.nvalt.round3.luu", "NVBuildFlavor": "development"}))
    run = subprocess.run([str(executable), str(temp)], capture_output=True, text=True, timeout=20)
    (HERE / "runtime-output.log").write_text(run.stdout + run.stderr)
    print(run.stdout + run.stderr, end="")
    run.check_returncode()
    report["observations"] = json.loads(run.stdout)
    for mode, values in report["observations"]["warm_open_microseconds"].items():
        report.setdefault("warm_summary_microseconds", {})[mode] = {"median": statistics.median(values[1:]), "minimum": min(values[1:]), "maximum": max(values[1:])}
(HERE / "results.json").write_text(json.dumps(report, indent=2) + "\n")
print("PASS: namespace filesystem work stayed on the worker; exact opener syscall counts and bounded timings recorded")
