#!/usr/bin/env python3
"""Frozen store checks for absent and stale selected parents before namespace creation."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
FROZEN = "47d18f4"


def run(command, timeout=45):
    completed = subprocess.run(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout)
    if completed.returncode:
        raise AssertionError((command, completed.returncode, completed.stdout.decode(), completed.stderr.decode()))
    return completed


report = {"commit": run(["git", "rev-parse", FROZEN]).stdout.decode().strip(),
          "source_sha256": {}, "runs": [], "assertions": 0}
with tempfile.TemporaryDirectory(prefix="nvalt-platform-round3-", dir=HERE) as temporary:
    temp = Path(temporary).resolve()
    for source in ("Sources/Storage/NVBackupStore.m", "Sources/Storage/NVBackupStore.h"):
        raw = run(["git", "show", FROZEN + ":" + source]).stdout
        (temp / Path(source).name).write_bytes(raw)
        report["source_sha256"][source] = hashlib.sha256(raw).hexdigest()
    for arch in ("arm64", "x86_64"):
        binary = temp / ("Probe-" + arch)
        run(["xcrun", "clang", "-arch", arch, "-fno-objc-arc", "-fblocks", "-Wno-deprecated-declarations",
             "-framework", "Foundation", "-I", str(temp), str(HERE / "probe.m"),
             str(temp / "NVBackupStore.m"), "-o", str(binary)])
        imports = run(["nm", "-u", str(binary)]).stdout.decode()
        assert "_SecKeychain" not in imports and "_OBJC_CLASS_$_NSUserDefaults" not in imports
        for flavor in ("release", "development"):
            data_root = temp / (arch + "-" + flavor + "-data")
            completed = run([str(binary), str(data_root), flavor], timeout=20)
            output = completed.stdout.decode()
            print(output, end="")
            count = int(re.search(r"ASSERTIONS:(\d+)", output).group(1))
            report["assertions"] += count
            report["runs"].append({"architecture": arch, "flavor": flavor, "assertions": count,
                                   "output": output, "stderr": completed.stderr.decode(), "exit_code": 0})
report["result"] = "PASS: absent and stale selected parents reject all three operations before child creation"
(HERE / "results.json").write_text(json.dumps(report, indent=2) + "\n")
print(report["result"] + "; " + str(report["assertions"]) + " native assertions")
