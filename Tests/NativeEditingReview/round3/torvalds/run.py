#!/usr/bin/env python3
"""Round-3 final deletion, target, and ownership audit."""

from pathlib import Path
import subprocess
import sys
import tempfile

import project_probe
import source_probe


REPO = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent


def check(condition, description):
    if not condition:
        print("FAIL:", description)
        raise SystemExit(1)
    print("PASS:", description)


subprocess.run(["git", "diff", "--check"], cwd=REPO, check=True)
print("PASS: working-tree diff has no whitespace errors")

project = project_probe.audit()
dangling = project["dangling_project_references"]
if dangling:
    print("FINDING P1: deleted files remain in the Xcode target")
    for path, lines in dangling.items():
        print(f"  {path}: project.pbxproj lines {', '.join(map(str, lines))}")
else:
    print("PASS: deleted patch files have no Xcode project references")

source = source_probe.audit()
check(not source["removed_preference_tokens"],
      "removed editor preferences have no production source references")
check(not source["unsupported_editor_compatibility"],
      "LinkingEditor has no unsupported pre-10.13 compatibility branches")
check(not source["finder_alloc_plus_retain"],
      "NSTextFinder ownership has no alloc-plus-retain leak")

if source["stale_order_entries"]:
    print("FINDING P3: order files still name removed LinkingEditor overrides")
    for symbol, matches in source["stale_order_entries"].items():
        print(f"  {symbol}: {', '.join(matches)}")
else:
    print("PASS: order files contain no removed LinkingEditor override symbols")

if source["orphan_highlight_helper"]:
    print("FINDING P3: highlightRangesTemporarily: has no caller")
    for match in source["highlight_helper_occurrences"]:
        print(" ", match)
else:
    print("PASS: no declaration/definition-only legacy highlight helper remains")

with tempfile.TemporaryDirectory(prefix="nvalt-r3-torvalds-build-") as temporary:
    command = [
        "xcodebuild", "-project", "Notation.xcodeproj", "-scheme", "Notation Develop",
        "-derivedDataPath", str(Path(temporary) / "DerivedData"),
        "ARCHS=x86_64", "MACOSX_DEPLOYMENT_TARGET=10.13", "CODE_SIGNING_ALLOWED=NO",
        "GENERATE_PROFILING_CODE=NO", "OTHER_CFLAGS=", "WARNING_LDFLAGS=", "build",
    ]
    built = subprocess.run(command, cwd=REPO, stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT, text=True)
    normalized = built.stdout.replace(str(REPO), "$REPO").replace(temporary, "$TMP")
    significant = [line for line in normalized.splitlines()
                   if ("IBeamInverted" in line or "Build input file cannot be found" in line
                       or line.startswith("** BUILD"))]
    (HERE / "output.txt").write_text("\n".join(significant) + "\n")
    if dangling:
        check(built.returncode != 0 and "IBeamInverted.png" in built.stdout
              and "Build input file cannot be found" in built.stdout,
              "fresh Xcode build reproduces the dangling-resource failure")
    else:
        check(built.returncode == 0, "fresh unsigned Intel Development build succeeds")

subprocess.run([sys.executable, str(REPO / "Tests/SourceEditing/run.py"), "--compile-only"],
               cwd=REPO, check=True)
print("PASS: native source-editing integration probe compiles")
