#!/usr/bin/env python3
"""Compile extracted production methods and test their native ownership graph."""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

repo = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(repo / "Tests"))
from compiler_support import include_flags

source_dir = Path(__file__).resolve().parent
output = repo / "build/TitlebarReview/round1/ousterhout"
output.mkdir(parents=True, exist_ok=True)
ui_path = repo / "Sources/Browser/AppController_BrowserUI.m"
controller_path = repo / "Sources/Browser/AppController.m"
ui = ui_path.read_text()
controller = controller_path.read_text()
setup = ui[ui.index("- (void)setDualFieldInToolbar {"):ui.index("- (IBAction)setSystemColorScheme:")]
focus = controller[controller.index("- (void)selectSearchField {"):]
focus = focus[:focus.index("\n}") + 2]
teardown = controller[controller.index("- (void)dealloc {"):]
teardown = teardown[:teardown.index("\n}") + 2]
methods = setup + "\n" + focus + "\n" + teardown + "\n"
record = {
    "head": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip(),
    "source_sha256": {str(p.relative_to(repo)): hashlib.sha256(p.read_bytes()).hexdigest()
                      for p in (ui_path, controller_path, repo / "Sources/UI/DualField.m", repo / "Sources/Browser/AppController.h")},
    "extracted_methods_sha256": hashlib.sha256(methods.encode()).hexdigest(),
    "variants": {},
}
for name, extracted in (
    ("production", methods),
    ("leaked-container-negative-control", methods.replace("[searchContainer release];", "/* Deliberately leak the allocated container. */")),
):
    variant = output / name
    variant.mkdir(exist_ok=True)
    (variant / "production.inc").write_text(extracted)
    binary = variant / "OwnershipProbe"
    command = ["xcrun", "clang", "-arch", "arm64", "-fno-objc-arc", "-Wno-deprecated-declarations",
               "-Wno-incomplete-implementation", *include_flags(repo), "-I", str(variant),
               "-include", str(repo / "Config/Notation_Prefix.pch"), "-framework", "Cocoa", "-framework", "Carbon",
               "-o", str(binary), str(source_dir / "probe.m"), str(repo / "Sources/UI/DualField.m")]
    with (variant / "compile.log").open("w") as log:
        subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=True, cwd=repo)
    lock_path = repo / "build/pr-review/gui.lock"
    lock_path.parent.mkdir(exist_ok=True, parents=True)
    with lock_path.open("w") as lock, (variant / "run.log").open("w") as log:
        fcntl.flock(lock, fcntl.LOCK_EX)
        result = subprocess.run([str(binary)], stdout=log, stderr=subprocess.STDOUT, cwd=repo, timeout=30)
    record["variants"][name] = {"exit_code": result.returncode,
        "passes": (variant / "run.log").read_text().count("PASS "),
        "extracted_methods_sha256": hashlib.sha256(extracted.encode()).hexdigest()}
    print(name, record["variants"][name])
(output / "source-record.json").write_text(json.dumps(record, indent=2) + "\n")
assert record["variants"]["production"]["exit_code"] == 0, "production contract failed"
assert record["variants"]["leaked-container-negative-control"]["exit_code"] != 0, "negative control was not detected"
