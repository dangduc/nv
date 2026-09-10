#!/usr/bin/env python3
"""Compare exact current/base display delegates without opening an application."""
import hashlib
import json
import pathlib
import subprocess
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[3]
FILES = ["Sources/Browser/AppController.m", "Sources/Browser/AppController_Search.m",
         "Sources/Editor/LinkingEditor.h", "Sources/Editor/LinkingEditor.m"]
BASE = "54ce3b8f94c382e8a4c20c871b8fb20dc30cc376"


def hashes():
    return {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in FILES}


def method(source, signature):
    start = source.index(signature)
    end = source.index("{", start) + 1
    depth = 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


before = hashes()
source = (ROOT / FILES[-1]).read_text()
base = subprocess.check_output(["git", "show", BASE + ":" + FILES[-1]], cwd=ROOT, text=True)
display_signature = "- (NSDictionary *)layoutManager:(NSLayoutManager *)manager shouldUseTemporaryAttributes:"
display = method(source, display_signature)
base_display = method(base, display_signature).replace("layoutManager:", "baselineLayoutManager:", 1)
signatures = ["- (NSColor *)sourceColorForCapture:", "- (void)invalidateSearchHighlights {",
              "- (void)removeHighlightedTerms {", "- (void)setSearchHighlightRanges:"]
support = "\n".join(method(source, s) for s in signatures)
highlighter = (ROOT / "Sources/Editor/NVSourceHighlighter.m").read_text()
revision_support = highlighter[highlighter.index("NSString * const NVSourceCaptureAttributeName"):highlighter.index("BOOL NVSourceCapturesAreCurrent")]
template = (HERE / "probe.m.in").read_text()
cases = {"production": display,
         "missing_suppression": display.replace("searchHighlightsInvalidated &&", "NO &&", 1),
         "drop_other_attributes": display.replace("attributes = display;", "attributes = @{};", 1),
         "suppress_fresh_background": display.replace("searchHighlightsInvalidated &&", "YES &&", 1),
         "suppress_only_screen": display.replace("searchHighlightsInvalidated &&", "screen && searchHighlightsInvalidated &&", 1),
         "ignore_marked_ownership": display.replace("if (NSLocationInRange(index, marked))", "if (NO)", 1)}
results = []
with tempfile.TemporaryDirectory(prefix="nv-backspace-display-matrix-") as directory:
    directory = pathlib.Path(directory)
    for name, candidate in cases.items():
        assert name == "production" or candidate != display
        generated = template.replace("/* REVISION_SUPPORT */", revision_support).replace(
            "/* PRODUCTION_SUPPORT */", support).replace("/* CURRENT_DELEGATE */", candidate).replace(
            "/* BASE_DELEGATE */", base_display)
        src, binary = directory / (name + ".m"), directory / name
        src.write_text(generated)
        compile_result = subprocess.run(["xcrun", "clang", "-arch", "x86_64", "-fno-objc-arc",
            "-Wall", "-Wextra", "-Werror", "-Wno-unused-parameter", "-framework", "Cocoa",
            str(src), "-o", str(binary)], text=True, capture_output=True)
        (HERE / (name + "-compile.txt")).write_text(compile_result.stdout + compile_result.stderr)
        compile_result.check_returncode()
        result = subprocess.run([str(binary)], text=True, capture_output=True, timeout=20)
        (HERE / (name + ".txt")).write_text(result.stdout + result.stderr)
        results.append({"case": name, "exit_code": result.returncode,
                        "generated_sha256": hashlib.sha256(generated.encode()).hexdigest()})
        print(name, result.returncode, result.stdout.strip())
        assert (result.returncode == 0) == (name == "production"), name
after = hashes()
manifest = {"base": BASE, "head": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
            "production_sha256_before": before, "production_sha256_after": after,
            "unchanged": before == after, "extracted_methods": [display_signature, *signatures],
            "source_capture_revision_sha256": hashlib.sha256(revision_support.encode()).hexdigest(),
            "baseline_delegate_sha256": hashlib.sha256(base_display.encode()).hexdigest(),
            "cases": results, "platform": subprocess.check_output(["sw_vers"], text=True).strip(),
            "architecture": "x86_64 through Rosetta"}
(HERE / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
assert before == after, "production changed during review"
