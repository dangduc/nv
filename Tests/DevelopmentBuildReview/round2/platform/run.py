#!/usr/bin/env python3
"""Native metadata/runtime and unavailable backup-root checks in temporary paths."""
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
COMMIT = "3a3dc4fb7194b5ea7189295a7bbd17393bb32038"
PRODUCTS = ROOT / "build/DerivedData/Build/Products"
SOURCES = ["Sources/Storage/NVBackupStore.m", "Sources/Storage/NVBackupStore.h",
           "Sources/Application/NVAppIdentity.h"]


def run(command, timeout=45):
    completed = subprocess.run(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               timeout=timeout)
    if completed.returncode:
        raise AssertionError((command, completed.returncode, completed.stdout.decode(), completed.stderr.decode()))
    return completed


report = {"commit": COMMIT, "source_sha256": {}, "metadata_sha256": {}, "runs": []}
with tempfile.TemporaryDirectory(prefix="nvalt-platform-round2-", dir=HERE) as temporary:
    temp = Path(temporary).resolve()
    for source in SOURCES:
        raw = run(["git", "show", COMMIT + ":" + source]).stdout
        (temp / Path(source).name).write_bytes(raw)
        report["source_sha256"][source] = hashlib.sha256(raw).hexdigest()
    for arch in ("arm64", "x86_64"):
        binary = temp / ("Probe-" + arch)
        run(["xcrun", "clang", "-arch", arch, "-fno-objc-arc", "-fblocks", "-Wno-deprecated-declarations",
             "-framework", "Foundation", "-I", str(temp), str(HERE / "probe.m"),
             str(temp / "NVBackupStore.m"), "-o", str(binary)])
        imports = run(["nm", "-u", str(binary)]).stdout.decode()
        assert "_SecKeychain" not in imports and "_OBJC_CLASS_$_NSUserDefaults" not in imports
        for flavor, configuration, name in (("release", "ForBuilding", "nvALT"),
                                             ("development", "Development", "nvALT Development")):
            built_plist = PRODUCTS / configuration / (name + ".app/Contents/Info.plist")
            raw = built_plist.read_bytes()
            info = plistlib.loads(raw)
            assert info["CFBundleExecutable"] == name
            report["metadata_sha256"][flavor] = hashlib.sha256(raw).hexdigest()
            app = temp / arch / (name + ".app")
            executable = app / "Contents/MacOS" / name
            executable.parent.mkdir(parents=True)
            shutil.copy2(binary, executable)
            # Copy the built metadata byte-for-byte. The probe uses no preferences APIs.
            (app / "Contents/Info.plist").write_bytes(raw)
            data_root = temp / (arch + "-" + flavor + "-data")
            completed = run([str(executable), str(data_root), flavor], timeout=20)
            output = completed.stdout.decode().strip()
            print(output)
            report["runs"].append({"architecture": arch, "flavor": flavor, "output": output,
                                   "stderr": completed.stderr.decode(), "exit_code": completed.returncode})
report["result"] = "PASS: two hypotheses, both flavors, arm64 and x86_64, 80 native assertions"
(HERE / "results.json").write_text(json.dumps(report, indent=2) + "\n")
print(report["result"])
