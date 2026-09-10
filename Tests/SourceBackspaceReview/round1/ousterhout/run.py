#!/usr/bin/env python3
"""Run exact production cleanup methods against real AppKit storage and layout.

No application or window is created. The adapter substitutes editor ownership,
not the cleanup methods, run loop, temporary-attribute storage, or edit batching.
"""
import hashlib
import json
import pathlib
import subprocess
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[3]
FILES = [
    "Sources/Browser/AppController.m",
    "Sources/Browser/AppController_Search.m",
    "Sources/Editor/LinkingEditor.h",
    "Sources/Editor/LinkingEditor.m",
]


def hashes():
    return {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in FILES}


def method(source, signature):
    start = source.index(signature)
    brace = source.index("{", start)
    level = 1
    end = brace + 1
    while level:
        if source[end] == "{":
            level += 1
        elif source[end] == "}":
            level -= 1
        end += 1
    return source[start:end]


before = hashes()
source = (ROOT / "Sources/Editor/LinkingEditor.m").read_text()
signatures = [
    "- (void)invalidateSearchHighlights {",
    "- (void)removeHighlightedTerms {",
    "- (void)setSearchHighlightRanges:(NSArray *)ranges {",
    "- (NSDictionary *)layoutManager:(NSLayoutManager *)manager shouldUseTemporaryAttributes:",
]
methods = "\n\n".join(method(source, signature) for signature in signatures)
template = (HERE / "probe.m.in").read_text()
assert template.count("/* PRODUCTION_METHODS */") == 1
generated = template.replace("/* PRODUCTION_METHODS */", methods)
with tempfile.TemporaryDirectory(prefix="nv-backspace-ownership-") as directory:
    directory = pathlib.Path(directory)
    objective_c = directory / "probe.m"
    executable = directory / "probe"
    objective_c.write_text(generated)
    compile_result = subprocess.run(
        ["xcrun", "clang", "-arch", "x86_64", "-fno-objc-arc", "-framework", "Cocoa", "-o", str(executable), str(objective_c)],
        text=True, capture_output=True,
    )
    (HERE / "compile.txt").write_text(compile_result.stdout + compile_result.stderr)
    compile_result.check_returncode()
    result = subprocess.run([str(executable)], text=True, capture_output=True, timeout=30)
    (HERE / "output.txt").write_text(result.stdout + result.stderr)
    after = hashes()
    manifest = {
        "base": subprocess.check_output(["git", "rev-parse", "54ce3b8"], cwd=ROOT, text=True).strip(),
        "head": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "production_sha256_before": before,
        "production_sha256_after": after,
        "unchanged": before == after,
        "extracted_methods": signatures,
        "generated_probe_sha256": hashlib.sha256(generated.encode()).hexdigest(),
        "platform": subprocess.check_output(["sw_vers"], text=True).strip(),
        "architecture": "x86_64 through Rosetta",
        "exit_code": result.returncode,
        "limitations": [
            "Adapter uses NSObject rather than LinkingEditor and does not create a browser or window.",
            "Rendering check invokes the exact delegate method with screen=NO; syntax and IME branches are outside this probe.",
            "This host is macOS 26; the reported macOS 13 crash is not rerun here.",
        ],
    }
    (HERE / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(result.stdout, end="")
    print(result.stderr, end="")
    result.check_returncode()
    assert before == after, "production changed during the review probe"
