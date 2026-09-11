#!/usr/bin/env python3
"""Bounded independent process histories; only temporary files and UUID defaults domains."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import json
import plistlib
import re
import shutil
import subprocess
import tempfile
import uuid

here = Path(__file__).resolve().parent
repo = here.parents[3]
production = subprocess.check_output(["git", "show", "2dbfd46:Sources/Storage/NVBackupController.m"], cwd=repo, text=True)


def method(signature):
    start = production.index(signature)
    boundary = re.search(r"\n[+-] \(", production[start + len(signature):])
    assert boundary, signature
    return production[start:start + len(signature) + boundary.start()].strip()


helpers = production[production.index("NSString * const NVBackupStatus"):production.index("@implementation NVBackupController")]
signatures = ["- (void)changed", "- (void)scheduleNextAttemptAfterDelay:", "- (void)saveSettings", "- (void)setLibrary:", "- (NSURL *)rootURLWithError:", "- (NSURL *)destinationURL"]
methods = "\n".join(method(signature) for signature in signatures)
methods = methods.replace("NotationController", "ProbeLibrary").replace("NotationPrefs", "ProbePrefs")
source = (here / "probe.m").read_text().replace("@HELPERS@", helpers).replace("@METHODS@", methods)
domains = []
history = []
try:
    with tempfile.TemporaryDirectory(prefix="nvalt-kingsbury-review-") as temporary:
        root = Path(temporary).resolve()
        harness = root / "Probe.m"
        harness.write_text(source)
        binary = root / "Probe"
        subprocess.run(["xcrun", "clang", "-fno-objc-arc", "-Wno-deprecated-declarations", "-framework", "Cocoa", str(harness), "-o", str(binary)], check=True, timeout=60)
        apps = {}
        for flavor in ("release", "development"):
            executable = root / (flavor + ".app") / "Contents/MacOS/Probe"
            executable.parent.mkdir(parents=True)
            shutil.copy2(binary, executable)
            domain = "org.nvalt.kingsbury-review." + flavor + "." + uuid.uuid4().hex
            domains.append(domain)
            (executable.parent.parent / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": domain, "CFBundleExecutable": "Probe", "CFBundlePackageType": "APPL", "NVBuildFlavor": flavor}))
            apps[flavor] = executable

        def run(flavor, command):
            result = subprocess.run([str(apps[flavor]), str(root), flavor, command], capture_output=True, text=True, timeout=20)
            if result.returncode:
                raise RuntimeError((flavor, command, result.returncode, result.stdout, result.stderr))
            entry = {"flavor": flavor, "command": command, "stdout": result.stdout.strip(), "stderr": result.stderr.strip()}
            history.append(entry)
            print(result.stdout, end="", flush=True)
            return entry

        # Both processes use real NSUserDefaults, with independent fresh domains.
        with ThreadPoolExecutor(max_workers=2) as workers:
            list(workers.map(lambda flavor: run(flavor, "seed"), apps))
        for flavor in apps:
            run(flavor, "read")
        paths = {}
        for flavor in apps:
            first = run(flavor, "destination")["stdout"].split("DESTINATION:")[1].splitlines()[0]
            second = run(flavor, "destination-relaunch")["stdout"].split("DESTINATION:")[1].splitlines()[0]
            assert first == second, (first, second)
            paths[flavor] = first
        assert paths["release"] == paths["development"], paths
        run("release", "copy-control")
        report = {"commit": "2dbfd46", "hypothesis_1": "PASS: independent backup settings/claims and alias bytes survive process relaunch", "hypothesis_2": "COLLISION CONFIRMED: separate physical note copies, same UUID, same custom backup root resolve to the same destination across domains", "destinations": paths, "history": history, "limits": "Foundation processes and verbatim extracted production backup methods; no actual app startup, encrypted archive, real keychain, or retention mutation. Claims and preferences are only unique test domains. Temporary filesystem paths are removed."}
        (here / "results.json").write_text(json.dumps(report, indent=2) + "\n")
        print(report["hypothesis_1"])
        print(report["hypothesis_2"])
finally:
    for domain in domains:
        assert domain.startswith("org.nvalt.kingsbury-review.")
        subprocess.run(["defaults", "delete", domain], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
