#!/usr/bin/env python3
"""Frozen native backup preflight and wiki-prefix checks; disposable paths only."""
from pathlib import Path
import json
import plistlib
import re
import shutil
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
COMMIT = "3a3dc4fb7194b5ea7189295a7bbd17393bb32038"


def source(path):
    return subprocess.check_output(["git", "show", f"{COMMIT}:{path}"], cwd=REPO, text=True)


def method(text, signature):
    start = text.index(signature)
    boundary = re.search(r"\n[+-] \(", text[start + len(signature):])
    assert boundary, signature
    return text[start:start + len(signature) + boundary.start()].strip()


backup = source("Sources/Storage/NVBackupController.m")
helpers = backup[backup.index("static NSError *BackupError"):backup.index("static NSString *DateLabel")]
signatures = ["- (NSURL *)rootURLWithError:", "- (NSURL *)destinationURL",
              "- (NSURL *)checkedDestinationWithError:"]
methods = "\n".join(method(backup, signature) for signature in signatures)
begin = method(backup, "- (void)beginBackupAtDate:")
# Preserve the complete production preflight. The observation point replaces
# snapshot capture and the asynchronous writer, after every relevant guard.
preflight = begin[:begin.index("    NSDictionary *snapshot =")] + "    SnapshotBoundaryReached = YES;\n}\n"
editor = source("Sources/Editor/AttributedPlainText.m")
scan_start = editor.index("- (void)_addDoubleBracketedNVLinkAttributesForRange:")
helper_start = editor.index("\nstatic BOOL _StringWithRangeIsProbablyObjC", scan_start)
scan = editor[scan_start:helper_start]
wiki_helper = editor[helper_start:editor.index("- (void)addStrikethroughNearDoneTagsForRange:", helper_start)]
strings = source("Sources/Utilities/NSString_NV.m")
escape = strings[strings.index("- (NSString*)stringWithPercentEscapes {"):strings.index("+ (NSString*)reasonStringFromCarbonFSError:")]
template = (HERE / "probe.m").read_text()
for token, value in {"@IDENTITY@": source("Sources/Application/NVAppIdentity.h"),
                     "@HELPERS@": helpers, "@METHODS@": methods,
                     "@PREFLIGHT@": preflight, "@SCAN@": scan,
                     "@WIKI_HELPER@": wiki_helper, "@ESCAPE@": escape}.items():
    template = template.replace(token, value)
assert not re.search(r"@[A-Z_]+@", template)

report = {"commit": COMMIT, "environment": subprocess.check_output(["sw_vers"], text=True).strip(),
          "xcode": subprocess.check_output(["xcodebuild", "-version"], text=True).strip(),
          "architecture": "arm64 native", "runs": []}
with tempfile.TemporaryDirectory(prefix="nvalt-ousterhout-round2-") as temporary:
    root = Path(temporary).resolve()
    harness = root / "Probe.m"
    binary = root / "Probe"
    harness.write_text(template)
    subprocess.run(["xcrun", "clang", "-arch", "arm64", "-fno-objc-arc", "-fblocks",
                    "-Wno-deprecated-declarations", "-framework", "Cocoa", str(harness), "-o", str(binary)],
                   check=True, timeout=60)
    imports = subprocess.check_output(["nm", "-u", str(binary)], text=True)
    assert "_SecKeychain" not in imports
    assert "_OBJC_CLASS_$_NSUserDefaults" not in imports
    for flavor in ("development", "release", "missing"):
        executable = root / (flavor + ".app") / "Contents/MacOS/Probe"
        executable.parent.mkdir(parents=True)
        shutil.copy2(binary, executable)
        info = {"CFBundleExecutable": "Probe", "CFBundlePackageType": "APPL",
                "CFBundleIdentifier": "org.nvalt.ousterhout.round2.copied." + flavor}
        if flavor != "missing":
            info["NVBuildFlavor"] = flavor
        (executable.parent.parent / "Info.plist").write_bytes(plistlib.dumps(info))
        run = subprocess.run([str(executable), str(root), flavor], capture_output=True, text=True, timeout=30)
        print(run.stdout, end="", flush=True)
        if run.stderr:
            print(run.stderr, end="", flush=True)
        report["runs"].append({"flavor": flavor, "exit_code": run.returncode,
                               "stdout": run.stdout, "stderr": run.stderr})
        assert run.returncode == 0, report["runs"][-1]
report["result"] = "PASS: all observations matched; development custom-root first-backup regression reproduced"
(HERE / "results.json").write_text(json.dumps(report, indent=2) + "\n")
print(report["result"])
