#!/usr/bin/env python3
"""Measure exact cleanup methods with real AppKit storage, without a GUI app."""
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

here = Path(__file__).resolve().parent
repo = here.parents[3]
files = ["Sources/Browser/AppController.m", "Sources/Browser/AppController_Search.m",
         "Sources/Editor/LinkingEditor.h", "Sources/Editor/LinkingEditor.m"]


def hashes():
    return {f: hashlib.sha256((repo / f).read_bytes()).hexdigest() for f in files}


def method(source, signature):
    start = source.index(signature)
    end = source.index("{", start) + 1
    level = 1
    while level:
        level += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


before = hashes()
source = (repo / files[-1]).read_text()
signatures = ["- (void)invalidateSearchHighlights {", "- (void)removeHighlightedTerms {",
              "- (NSDictionary *)layoutManager:(NSLayoutManager *)manager shouldUseTemporaryAttributes:"]
legacy = subprocess.check_output(["git", "show", "54ce3b8:" + files[-1]], cwd=repo, text=True)
generated = (here / "probe.m.in").read_text().replace(
    "/* PRODUCTION_METHODS */", "\n".join(method(source, s) for s in signatures)).replace(
    "/* LEGACY_METHOD */", method(legacy, "- (void)removeHighlightedTerms {").replace(
        "removeHighlightedTerms", "legacyRemoveHighlightedTerms", 1))
with tempfile.TemporaryDirectory(prefix="nv-backspace-cost-") as directory:
    directory = Path(directory)
    probe = directory / "probe.m"
    executable = directory / "probe"
    probe.write_text(generated)
    compiled = subprocess.run(["xcrun", "clang", "-arch", "x86_64", "-fno-objc-arc",
                               "-O2", "-framework", "Cocoa", "-o", str(executable), str(probe)],
                              text=True, capture_output=True)
    (here / "compile.txt").write_text(compiled.stdout + compiled.stderr)
    compiled.check_returncode()
    result = subprocess.run([str(executable)], capture_output=True, text=True, timeout=30)
    (here / "output.txt").write_text(result.stdout + result.stderr)
after = hashes()
(here / "manifest.json").write_text(json.dumps({
    "base": "54ce3b8", "production_sha256_before": before, "production_sha256_after": after,
    "unchanged": before == after, "generated_probe_sha256": hashlib.sha256(generated.encode()).hexdigest(),
    "exit_code": result.returncode, "platform": subprocess.check_output(["sw_vers"], text=True).strip(),
    "architecture": "x86_64 through Rosetta", "production_methods": signatures,
    "bounds": ["Native AppKit storage/layout; NSObject adapter for editor ownership, no window or browser.",
               "Counts are assertions; elapsed durations are descriptive and have no pass/fail threshold.",
               "Safe legacy comparison sends invalidations between edits; it does not repeat the known crash.",
               "Drawing probe calls exact delegate with screen=NO to isolate new dictionary-copy branch.",
               "Nested-edit probe deliberately pumps a run loop across beginEditing/endEditing; user path frequency is unknown."]
}, indent=2) + "\n")
print(result.stdout, end="")
print(result.stderr, end="")
assert before == after, "production changed during probe"
result.check_returncode()
