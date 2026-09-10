#!/usr/bin/env python3
"""Round-two mixed NSTextStorage notification review; no application or GUI."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
FILES = ["Sources/Browser/AppController.m", "Sources/Browser/AppController_Search.m",
         "Sources/Editor/LinkingEditor.h", "Sources/Editor/LinkingEditor.m"]
def hashes():
    return {name: hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in FILES}
def method(source, signature):
    start = source.index(signature)
    end = source.index("{", start) + 1
    depth = 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]
def revision():
    return subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()

before, head_before = hashes(), revision()
editor_source = (ROOT/FILES[3]).read_text()
editor_signatures = ["- (void)invalidateSearchHighlights {", "- (void)removeHighlightedTerms {",
                     "- (void)setSearchHighlightRanges:(NSArray *)ranges {"]
editor = "\n\n".join(method(editor_source, name) for name in editor_signatures)
observer_signature = "- (void)searchSourceStorageWillProcessEditing:(NSNotification *)notification {"
observer = method((ROOT/FILES[1]).read_text(), observer_signature)
template = (HERE/"probe.m.in").read_text()
source = template.replace("/* EDITOR_METHODS */", editor).replace("/* OBSERVER_METHOD */", observer)
variants = {
    "candidate-native-sanitize": (source, ["-arch", "arm64", "-fsanitize=address,undefined", "-fno-omit-frame-pointer"]),
    "candidate-intel": (source, ["-arch", "x86_64"]),
    "control-mask-equality": (source.replace("if ([[self textStorage] editedMask] & NSTextStorageEditedCharacters)", "if ([[self textStorage] editedMask] == NSTextStorageEditedCharacters)"), ["-arch", "arm64", "-fsanitize=address,undefined", "-fno-omit-frame-pointer"]),
    "control-attribute-invalidation": (source.replace("|| !([storage editedMask] & NSTextStorageEditedCharacters)", "|| ![storage editedMask]"), ["-arch", "arm64", "-fsanitize=address,undefined", "-fno-omit-frame-pointer"]),
}
results = {}
with tempfile.TemporaryDirectory(prefix="nv-backspace-r2-notifications-") as directory:
    directory = Path(directory)
    for name, (body, flags) in variants.items():
        if name.startswith("control-"):
            assert body != source, "Control does not apply: " + name
        path, executable = directory/(name+".m"), directory/name
        path.write_text(body)
        command = ["xcrun", "clang", "-O1", "-g", "-Wall", "-Wextra", "-Werror", "-fno-objc-arc", *flags,
                   "-framework", "Cocoa", str(path), "-o", str(executable)]
        compiled = subprocess.run(command, capture_output=True, text=True)
        (HERE/(name+"-compile.txt")).write_text(compiled.stdout+compiled.stderr)
        compiled.check_returncode()
        env = dict(os.environ, ASAN_OPTIONS="detect_leaks=0:halt_on_error=1", UBSAN_OPTIONS="halt_on_error=1")
        result = subprocess.run([str(executable)], env=env, capture_output=True, text=True, timeout=20)
        (HERE/(name+"-output.txt")).write_text(result.stdout+result.stderr)
        results[name] = {"exit_code": result.returncode, "generated_sha256": hashlib.sha256(body.encode()).hexdigest(),
                         "flags": flags, "last_line": result.stdout.strip().splitlines()[-1] if result.stdout.strip() else ""}
        print(name, results[name])
after = hashes()
manifest = {"head_before": head_before, "head_after": revision(), "base": "54ce3b8f94c382e8a4c20c871b8fb20dc30cc376",
            "production_sha256_before": before, "production_sha256_after": after, "production_unchanged": before == after,
            "platform": subprocess.check_output(["sw_vers"], text=True).strip(),
            "extracted_methods": editor_signatures+[observer_signature], "variants": results,
            "limitations": ["NSObject adapter supplies editor ownership; storage, layout, notifications and run loop are AppKit.",
                            "No browser, text view, window drawing or input method is exercised.",
                            "ASan leak detection is disabled; ownership checks observe deterministic destruction.",
                            "This host is macOS 26.5.2; macOS 13.7.8 is untested."]}
(HERE/"manifest.json").write_text(json.dumps(manifest, indent=2)+"\n")
assert before == after, "Production changed during the probe"
for name, result in results.items():
    assert (result["exit_code"] == 0) == name.startswith("candidate-"), (name, result)
