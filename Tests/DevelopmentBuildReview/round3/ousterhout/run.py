#!/usr/bin/env python3
"""Exercise first custom backup publication in frozen, complete app copies."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import uuid

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--commit", default="47d18f43cadb1a2eeeed9c7fbe379795c76faae7",
                    help="Frozen commit for the injected isolation harness")
parser.add_argument("--output", type=Path, default=HERE,
                    help="Evidence directory for results.json and output/")
args = parser.parse_args()
COMMIT = subprocess.check_output(["git", "rev-parse", args.commit], cwd=REPO, text=True).strip()
EVIDENCE = args.output.resolve()


def source(path):
    return subprocess.check_output(["git", "show", f"{COMMIT}:{path}"], cwd=REPO, text=True)


def replace_once(text, old, new):
    assert text.count(old) == 1, (old, text.count(old))
    return text.replace(old, new)


base_runner = {"__name__": "frozen_isolation_runner",
               "__file__": str(REPO / "Tests/DevelopmentBuild/run-tests.py")}
exec(compile(source("Tests/DevelopmentBuild/run-tests.py"), "frozen-run-tests.py", "exec"), base_runner)
probe = source("Tests/DevelopmentBuild/IsolationProbe.m")
probe = replace_once(probe, "@interface NSObject (NVIsolationApp)",
                     (HERE / "custom-checks.m").read_text() + "\n@interface NSObject (NVIsolationApp)")
probe = replace_once(probe, "    @try {\n", "    @try {\n        CustomResults = [NSMutableDictionary dictionary];\n")
old_default = '''        Check([[[[backup destinationURL] path] stringByDeletingLastPathComponent] isEqualToString:Canonical([support stringByAppendingPathComponent:@"Backups"])],
            @"backup destination belongs to this build's support directory");'''
probe = replace_once(probe, old_default, '''        if ([Phase isEqualToString:@"first"]) {
''' + old_default + '''
        } else CheckCustomDestination(backup, @"automatic");''')
probe = replace_once(probe, '        Check(![backup isBusy], @"initial backup worker finishes");',
                     '''        Check(![backup isBusy], @"initial backup worker finishes");
        if (![Phase isEqualToString:@"first"]) {
            WaitForBackup(backup, @"relaunch");
            CheckPublishedPayload(backup, @"relaunch");
            Check(![[[backup settings] objectForKey:@"enabled"] boolValue], @"relaunch retains the disabled timer setting");
        }''')
probe = replace_once(probe, '            Check(![backup isBusy], @"manual backup finishes");',
                     '''            Check(![backup isBusy], @"manual backup finishes");
            WaitForBackup(backup, @"default");
            CheckPublishedPayload(backup, @"default");
            ExerciseFirstCustomBackup(backup, @"manual", NO);
            ExerciseFirstCustomBackup(backup, @"automatic", YES);''')
probe = replace_once(probe, '        Check([report writeToFile:ReportPath(@"ready.plist") atomically:YES],',
                     '''        [report setObject:CustomResults forKey:@"customPublication"];
        Check([report writeToFile:ReportPath(@"ready.plist") atomically:YES],''')

products = REPO / "build/DerivedData/Build/Products"
sources = {"development": products / "Development/nvALT Development.app",
           "release": products / "ForBuilding/nvALT.app"}
metadata = {flavor: base_runner["check_metadata"](app, flavor) for flavor, app in sources.items()}
output = EVIDENCE / "output"
output.mkdir(parents=True, exist_ok=True)
(output / "screenshots").mkdir(exist_ok=True)
common_git = Path(subprocess.check_output(["git", "rev-parse", "--path-format=absolute", "--git-common-dir"], cwd=REPO, text=True).strip())
lock_path = common_git.parent / "build/pr-review/gui.lock"
domains = []
report = {"commit": COMMIT, "architecture": "x86_64 applications under Rosetta",
          "environment": subprocess.check_output(["sw_vers"], text=True).strip(),
          "xcode": subprocess.check_output(["xcodebuild", "-version"], text=True).strip(),
          "executables_sha256": {flavor: hashlib.sha256((app / "Contents/MacOS" / metadata[flavor]["CFBundleExecutable"]).read_bytes()).hexdigest()
                                 for flavor, app in sources.items()}}
with lock_path.open("a") as lock, tempfile.TemporaryDirectory(prefix="nvalt-ousterhout-round3-", dir=REPO / "build") as temporary:
    print(f"Waiting for GUI lock: {lock_path}", flush=True)
    fcntl.flock(lock, fcntl.LOCK_EX)
    root = Path(temporary).resolve()
    for folder in ("Home/Library/Application Support", "Home/Library/Caches", "Home/Library/Preferences",
                   "Home/Documents", "Home/Desktop", "Home/.Trash", "Temp", "Custom-manual", "Custom-automatic"):
        (root / folder).mkdir(parents=True, exist_ok=True)
    apps = {}
    try:
        for flavor, original in sources.items():
            app = root / flavor / original.name
            shutil.copytree(original, app, symlinks=True)
            info = dict(metadata[flavor])
            domain = "org.nvalt.ousterhout-round3." + flavor + "." + uuid.uuid4().hex
            domains.append(domain)
            info["CFBundleIdentifier"] = domain
            (app / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
            apps[flavor] = app
        harness = root / "IsolationProbe.m"
        harness.write_text(probe)
        dylib = root / "IsolationProbe.dylib"
        subprocess.run(["xcrun", "clang", "-arch", "x86_64", "-mmacosx-version-min=10.13", "-dynamiclib",
                        "-undefined", "dynamic_lookup", "-fno-objc-arc", "-Wno-deprecated-declarations",
                        *base_runner["include_flags"](REPO), "-include", str(REPO / "Config/Notation_Prefix.pch"),
                        "-framework", "Cocoa", "-framework", "Carbon", "-framework", "Security",
                        "-o", str(dylib), str(harness)], check=True, timeout=60)
        report["first"] = base_runner["run_pair"](apps, root, dylib, output, "first")
        report["relaunch"] = base_runner["run_pair"](apps, root, dylib, output, "relaunch")
        for flavor in sources:
            for key in ("notes", "support", "cache", "backup", "editing", "bundleIdentifier"):
                assert report["first"][flavor][key] == report["relaunch"][flavor][key], (flavor, key)
            custom = report["first"][flavor]["customPublication"]
            restored = report["relaunch"][flavor]["customPublication"]["relaunchSnapshot"]
            assert custom["automaticSnapshot"] == restored, (flavor, custom, restored)
            assert len({custom[key] for key in ("defaultSnapshot", "manualSnapshot", "automaticSnapshot")}) == 3
        report["result"] = "PASS: actual default, first manual custom, first automatic custom publication and relaunch payloads"
        (EVIDENCE / "results.json").write_text(json.dumps(report, indent=2) + "\n")
        print(report["result"], flush=True)
    finally:
        for domain in domains:
            assert domain.startswith("org.nvalt.ousterhout-round3.")
            subprocess.run(["defaults", "delete", domain], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
