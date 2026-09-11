#!/usr/bin/env python3
"""Bounded independent process histories; only temporary files and UUID defaults domains."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import json
import hashlib
import plistlib
import re
import shutil
import subprocess
import tempfile
import uuid

here = Path(__file__).resolve().parent
repo = here.parents[3]
commit = "3a3dc4fb7194b5ea7189295a7bbd17393bb32038"
paths_to_capture = ["Sources/Storage/NVBackupController.m", "Sources/Application/NVAppIdentity.h",
                    "Sources/Storage/NVBackupStore.m", "Sources/Storage/NVBackupStore.h"]
frozen = {path:subprocess.check_output(["git", "show", commit + ":" + path], cwd=repo) for path in paths_to_capture}
before = {path:hashlib.sha256((repo/path).read_bytes()).hexdigest() for path in paths_to_capture}
production = frozen[paths_to_capture[0]].decode()


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
    # Avoid macOS /var and /private/var URL aliases in lexical path assertions.
    with tempfile.TemporaryDirectory(prefix="nvalt-kingsbury-review-", dir=here) as temporary:
        root = Path(temporary).resolve()
        harness = root / "Probe.m"
        harness.write_text(source)
        for path in paths_to_capture[1:]:
            (root / Path(path).name).write_bytes(frozen[path])
        binary = root / "Probe"
        compile_output = subprocess.run(["xcrun", "clang", "-fno-objc-arc", "-Wno-deprecated-declarations", "-framework", "Cocoa", str(harness), "-o", str(binary)], capture_output=True,text=True,timeout=60)
        (here / "compile.log").write_text(compile_output.stdout+compile_output.stderr)
        compile_output.check_returncode()
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
        parent = root / "shared-custom-backups"
        identifier = "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE"
        assert paths["release"] == str(parent / identifier), paths
        assert paths["development"] == str(parent / "nvALT Development" / identifier), paths
        assert paths["release"] != paths["development"], paths
        run("release", "copy-control")
        # These parents are intentionally present: another reviewer covers first backup creation.
        (parent / "nvALT Development").mkdir(exist_ok=True)
        retention_binary = root / "retention"
        retention_compile = subprocess.run(["xcrun", "clang", "-fblocks", "-fno-objc-arc", "-Wno-deprecated-declarations",
            "-framework", "Foundation", "-I",str(root), str(root/"NVBackupStore.m"), str(here/"retention.m"),
            "-o",str(retention_binary)], capture_output=True,text=True,timeout=60)
        with (here/"compile.log").open("a") as log:
            log.write(retention_compile.stdout+retention_compile.stderr)
        retention_compile.check_returncode()
        retention = subprocess.run([str(retention_binary),paths["release"],paths["development"]],capture_output=True,text=True,timeout=30)
        (here/"retention-output.log").write_text(retention.stdout+retention.stderr)
        retention.check_returncode()
        print(retention.stdout,end="")
        after = {path:hashlib.sha256((repo/path).read_bytes()).hexdigest() for path in paths_to_capture}
        assert before == after
        report = {"commit": commit, "original_commit":"2dbfd46", "hypothesis_1": "PASS: separate custom destinations and flavor settings survive process relaunch; same-domain copy control renews UUID", "hypothesis_2": "PASS: real backup-store pruning keeps the sibling flavor's snapshots and archive bytes unchanged", "destinations": paths, "history": history,
            "retention":retention.stdout.strip(), "source_hashes_before":before,"source_hashes_after":after,
            "frozen_source_hashes":{path:hashlib.sha256(data).hexdigest() for path,data in frozen.items()},
            "production_unchanged":before==after,
            "limits": "Headless Foundation processes with selected verbatim controller methods and the full frozen backup store; prepared custom parents, opaque disposable archive bytes, no actual app startup, archive decoding, keychain, or first-backup creation. Claims/preferences use unique test domains; all fixture dirs and domains are deleted."}
        (here / "results.json").write_text(json.dumps(report, indent=2) + "\n")
        (here / "runtime-output.log").write_text("\n".join(entry["stdout"]+"\n"+entry["stderr"] for entry in history)+"\n"+retention.stdout+retention.stderr)
        print(report["hypothesis_1"])
        print(report["hypothesis_2"])
finally:
    for domain in domains:
        assert domain.startswith("org.nvalt.kingsbury-review.")
        subprocess.run(["defaults", "delete", domain], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
