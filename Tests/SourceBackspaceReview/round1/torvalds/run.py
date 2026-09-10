#!/usr/bin/env python3
"""Independent range and callback-lifetime review against current AppKit methods."""
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
    depth, end = 1, brace + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


before = hashes()
source = (ROOT / "Sources/Editor/LinkingEditor.m").read_text()
signatures = [
    "- (void)invalidateSearchHighlights {",
    "- (void)removeHighlightedTerms {",
    "- (void)setSearchHighlightRanges:(NSArray *)ranges {",
]
methods = "\n\n".join(method(source, signature) for signature in signatures)
template = (HERE / "probe.m.in").read_text()
variants = {
    "candidate": methods,
    "no-cancellation": methods.replace(
        "[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(removeHighlightedTerms) object:nil];", ""
    ),
    "unsafe-edit-clear": methods.replace(
        "if ([[self textStorage] editedMask] & NSTextStorageEditedCharacters)", "if (NO)"
    ),
    "overflowing-range-check": methods.replace(
        "range.location <= length && range.length <= length - range.location && range.length",
        "range.location + range.length <= length && range.length",
    ),
}
results = {}
with tempfile.TemporaryDirectory(prefix="nv-backspace-ranges-") as directory:
    directory = pathlib.Path(directory)
    for name, body in variants.items():
        generated = template.replace("/* PRODUCTION_METHODS */", body)
        program = directory / (name + ".m")
        executable = directory / name
        program.write_text(generated)
        compiled = subprocess.run(
            ["xcrun", "clang", "-arch", "x86_64", "-fno-objc-arc", "-framework", "Cocoa", "-o", str(executable), str(program)],
            text=True, capture_output=True,
        )
        (HERE / (name + "-compile.txt")).write_text(compiled.stdout + compiled.stderr)
        compiled.check_returncode()
        result = subprocess.run([str(executable)], capture_output=True, text=True, timeout=30)
        (HERE / (name + "-output.txt")).write_text(result.stdout + result.stderr)
        results[name] = {
            "exit_code": result.returncode,
            "generated_sha256": hashlib.sha256(generated.encode()).hexdigest(),
            "last_line": result.stdout.strip().splitlines()[-1] if result.stdout.strip() else "",
        }
        print(name, results[name])

after = hashes()
manifest = {
    "base": subprocess.check_output(["git", "rev-parse", "54ce3b8"], cwd=ROOT, text=True).strip(),
    "head": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
    "production_sha256_before": before,
    "production_sha256_after": after,
    "unchanged": before == after,
    "architecture": "x86_64 through Rosetta",
    "platform": subprocess.check_output(["sw_vers"], text=True).strip(),
    "methods": signatures,
    "variants": results,
    "limitations": [
        "An NSObject adapter supplies editor ownership; the probe uses real NSTextStorage, NSLayoutManager, and the run loop.",
        "This is a method-level test. It does not create a browser or paint a window.",
        "The drawing delegate, input method, and actual AppController attachment path are outside this probe.",
        "The macOS 13 crash was not rerun on this macOS 26 host.",
    ],
}
(HERE / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
assert before == after, "Production changed during probe"
assert results["candidate"]["exit_code"] == 0, results["candidate"]
for name in variants:
    if name != "candidate":
        assert results[name]["exit_code"] != 0, "Sensitivity control passed: " + name
