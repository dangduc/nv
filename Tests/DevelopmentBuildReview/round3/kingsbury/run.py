#!/usr/bin/env python3
"""Run frozen backup-store histories in disposable headless flavor bundles."""
from pathlib import Path
import hashlib
import json
import plistlib
import re
import shutil
import subprocess
import tempfile
import uuid

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
COMMIT = "47d18f43cadb1a2eeeed9c7fbe379795c76faae7"
PATHS = ["Sources/Storage/NVBackupStore.m", "Sources/Storage/NVBackupStore.h", "Sources/Application/NVAppIdentity.h"]
frozen = {path:subprocess.check_output(["git", "show", COMMIT+":"+path], cwd=REPO) for path in PATHS}
before = {path:hashlib.sha256((REPO/path).read_bytes()).hexdigest() for path in PATHS}
history = []
with tempfile.TemporaryDirectory(prefix="history-",dir=HERE) as temporary:
    root=Path(temporary)
    selected=root/"selected-parent"
    selected.mkdir()
    for path,data in frozen.items():
        (root/Path(path).name).write_bytes(data)
    binary=root/"History"
    compilation=subprocess.run(["xcrun","clang","-fblocks","-fno-objc-arc","-Wno-deprecated-declarations",
        "-framework","Cocoa","-I",str(root),str(root/"NVBackupStore.m"),str(HERE/"history.m"),"-o",str(binary)],
        capture_output=True,text=True,timeout=60)
    (HERE/"compile.log").write_text(compilation.stdout+compilation.stderr)
    compilation.check_returncode()
    apps={}
    for flavor in ("release","development"):
        executable=root/(flavor+".app")/"Contents/MacOS/History"
        executable.parent.mkdir(parents=True)
        shutil.copy2(binary,executable)
        (executable.parent.parent/"Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier":"org.nvalt.kingsbury-review."+uuid.uuid4().hex,
            "CFBundleExecutable":"History","CFBundlePackageType":"APPL","NVBuildFlavor":flavor}))
        apps[flavor]=executable
    for flavor,command in [("release","seed"),("development","seed"),("development","prune"),
                           ("release","delete-republish"),("development","delete")]:
        result=subprocess.run([str(apps[flavor]),str(selected),str(root/"checkpoint.plist"),flavor,command],
            capture_output=True,text=True,timeout=20)
        entry={"flavor":flavor,"command":command,"exit_code":result.returncode,
            "stdout":result.stdout.strip(),"stderr":result.stderr.strip()}
        history.append(entry)
        (HERE/"runtime-output.log").write_text("\n".join(x["stdout"]+"\n"+x["stderr"] for x in history)+"\n")
        print(result.stdout,end="",flush=True)
        result.check_returncode()
    final=plistlib.loads((root/"checkpoint.plist").read_bytes())
    assert len(final["release"])==1 and len(final["development"])==0
    after={path:hashlib.sha256((REPO/path).read_bytes()).hexdigest() for path in PATHS}
    assert before==after=={path:hashlib.sha256(data).hexdigest() for path,data in frozen.items()}
    checks=sum(int(re.search(r"checks=(\d+)",x["stdout"])[1]) for x in history)
    report={"commit":COMMIT,"passed":True,"checks":checks,"processes":len(history),"history":history,
        "hypothesis_1":"PASS: first development publication creates its absent namespace and UUID directory beneath the selected parent",
        "hypothesis_2":"PASS: reopened interleaved pruning, plaintext deletion, and republication preserve every peer snapshot ID and archive byte",
        "final_snapshot_counts":{"release":len(final["release"]),"development":len(final["development"])},
        "source_hashes_before":before,"source_hashes_after":after,"production_unchanged":before==after,
        "limits":"Full frozen store with independently supplied caller metadata and frozen flavor helper. No full controller/app startup, archive decoding, defaults, user notes, keychain, GUI, root replacement, or concurrent failures. All fixture files are deleted."}
    (HERE/"results.json").write_text(json.dumps(report,indent=2)+"\n")
    print(f"PASS: {checks} checks across {len(history)} reopened process commands")
