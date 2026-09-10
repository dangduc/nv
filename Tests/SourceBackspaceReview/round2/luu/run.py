#!/usr/bin/env python3
"""Exercise retry cost and publication order with extracted production methods."""
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
    return {name: hashlib.sha256((repo / name).read_bytes()).hexdigest() for name in files}


def method(source, signature):
    start = source.index(signature)
    end = source.index("{", start) + 1
    depth = 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


before = hashes()
head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip()
source = (repo / files[-1]).read_text()
signatures = ["- (void)invalidateSearchHighlights {", "- (void)removeHighlightedTerms {",
              "- (void)setSearchHighlightRanges:(NSArray *)ranges {",
              "- (NSDictionary *)layoutManager:(NSLayoutManager *)manager shouldUseTemporaryAttributes:"]
editor_methods = "\n\n".join(method(source, item) for item in signatures)
observer_signature = "- (void)searchSourceStorageWillProcessEditing:(NSNotification *)notification {"
observer = method((repo / files[1]).read_text(), observer_signature)
template = (here / "probe.m.in").read_text()
variants = {
    "production": editor_methods,
    "zero-delay-retry": editor_methods.replace("afterDelay:0.01", "afterDelay:0"),
    "missing-cancellation": editor_methods.replace(
        "[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(removeHighlightedTerms) object:nil];", ""),
}
results = {}
with tempfile.TemporaryDirectory(prefix="nv-backspace-r2-cost-") as directory:
    directory = Path(directory)
    for name, body in variants.items():
        assert name == "production" or body != editor_methods
        generated = template.replace("/* EDITOR_METHODS */", body).replace("/* OBSERVER_METHOD */", observer)
        probe = directory / (name + ".m")
        executable = directory / name
        probe.write_text(generated)
        compiled = subprocess.run(["xcrun", "clang", "-arch", "x86_64", "-fno-objc-arc", "-O2",
                                   "-framework", "Cocoa", "-o", str(executable), str(probe)],
                                  capture_output=True, text=True)
        (here / (name + "-compile.txt")).write_text(compiled.stdout + compiled.stderr)
        compiled.check_returncode()
        result = subprocess.run([str(executable)] + ([] if name == "production" else ["control"]),
                                capture_output=True, text=True, timeout=30)
        (here / (name + ".txt")).write_text(result.stdout + result.stderr)
        results[name] = {"exit_code": result.returncode,
                         "generated_probe_sha256": hashlib.sha256(generated.encode()).hexdigest()}
        print(name + ":", result.stdout.strip())
after = hashes()
(here / "manifest.json").write_text(json.dumps({
    "head": head, "production_commit": "c2209e2", "production_sha256_before": before,
    "production_sha256_after": after, "unchanged": before == after, "variants": results,
    "platform": subprocess.check_output(["sw_vers"], text=True).strip(),
    "architecture": "x86_64 through Rosetta", "production_methods": signatures + [observer_signature],
    "bounds": ["Native AppKit storage and layout managers; NSObject editor/controller adapters; no GUI.",
               "Assertions use counts, requested callback delays, and attribute state, not a latency threshold.",
               "Both modes are registered as common modes; real app event routing is not exercised.",
               "Deliberate long editing batches test reentrancy, not its frequency in user workflows.",
               "Reported macOS 13.7.8 environment is not available on this host."]
}, indent=2) + "\n")
assert before == after, "production changed during probe"
assert results["production"]["exit_code"] == 0
for name in ("zero-delay-retry", "missing-cancellation"):
    assert results[name]["exit_code"] == 1, name + " did not fail the assertions"
