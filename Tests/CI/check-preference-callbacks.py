#!/usr/bin/env python3
"""Execute the production cached preference-callback dispatch on either CPU."""
import argparse
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "Tests"))
from compiler_support import include_flags

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--arch", choices=("x86_64", "arm64"), required=True)
args = parser.parse_args()
output = ROOT / "build/preference-callback-check" / args.arch
output.mkdir(parents=True, exist_ok=True)
source = (ROOT / "Sources/Preferences/GlobalPrefs.m").read_text()
start = source.index("static void sendCallbacksForGlobalPrefs(")
end = source.index("\n- (id)init", start)
assignment = next(line for line in source.splitlines() if "runCallbacksIMP =" in line)
(output / "dispatch.inc").write_text(source[start:end])
(output / "assignment.inc").write_text(assignment + "\n")
binary = output / "probe"
subprocess.run(["xcrun", "clang", "-arch", args.arch, "-fno-objc-arc", "-Werror",
                "-Wno-incomplete-implementation", "-framework", "Cocoa", *include_flags(ROOT),
                "-I" + str(output), str(ROOT / "Tests/CI/preference-callbacks.m"), "-o", str(binary)], check=True)
subprocess.run([str(binary)], check=True)
