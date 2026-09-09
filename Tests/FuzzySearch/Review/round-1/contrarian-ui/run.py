#!/usr/bin/env python3
"""Exercise production browser occurrences and asynchronous state with real fzf."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[5]
sys.path.insert(0, str(ROOT / "Tests"))
from compiler_support import include_flags

p = argparse.ArgumentParser()
p.add_argument("--sanitize", action="store_true")
p.add_argument("--baseline-inline", action="store_true")
p.add_argument("--expect-inline-preserved", action="store_true")
p.add_argument("--arch", choices=["arm64", "x86_64"])
a = p.parse_args()
out = ROOT / "build/FuzzySearchContrarianUI" / ("sanitize" if a.sanitize else a.arch or "native")
out.mkdir(parents=True, exist_ok=True)
baseline_source = subprocess.check_output(["git", "show", "a9539cc:Sources/UI/NotesTableView.m"], text=True) if a.baseline_inline else None
table_source = (ROOT / "Sources/UI/NotesTableView.m").read_text()
selection_methods = []
for prefix in ["- (BOOL)searchRowsAreAvailable", "- (NSInteger)primarySelectedRow", "- (void)setPrimarySelectedRow:",
               "- (void)preparePrimarySelectionForRow:", "- (void)notifyPrimaryChangeFromKey:", "- (void)selectRowIndexes:",
               "- (void)selectRowAndScroll:", "- (void)keyDown:", "- (NSMenu *)menuForEvent:",
               "- (void)clearInlineEditTarget", "- (NoteObject *)noteForInlineEditAtRow:", "- (BOOL)hasInlineEditTarget",
               "- (void)editColumn:", "- (void)textDidEndEditing:", "- (BOOL)abortEditing"]:
    active_source = baseline_source if baseline_source and prefix == "- (void)editColumn:" else table_source
    start = active_source.index(prefix)
    brace = active_source.index("{", start)
    end = brace + 1
    depth = 1
    while depth:
        depth += (active_source[end] == "{") - (active_source[end] == "}")
        end += 1
    selection_methods.append(active_source[start:end])
(out / "primary-selection.inc").write_text("\n".join(selection_methods))
controller_source = (ROOT / "Sources/Browser/AppController.m").read_text()
tag_methods = []
for prefix in ["- (void)captureMultiTagNotes:", "- (NSArray *)pendingMultiTagNotes", "- (void)cancelMultiTagEditing",
               "- (IBAction)multiTag:", "- (void)releaseTagEditor:"]:
    start = controller_source.index(prefix)
    tag_methods.append(controller_source[start:controller_source.index("\n}", start) + 2])
(out / "multi-tag.inc").write_text("\n".join(tag_methods))
flags = (["-DEXPECT_INLINE_PRESERVED=1"] if a.expect_inline_preserved else []) + (["-DBASELINE_INLINE=1"] if a.baseline_inline else []) + ["-g", "-O1" if a.sanitize else "-O2", "-DUTF8PROC_STATIC", "-I" + str(out), "-I" + str(ROOT / "ThirdParty/fzf-native"), *include_flags(ROOT)]
if a.arch:
    flags += ["-arch", a.arch]
if a.sanitize:
    flags += ["-fsanitize=address,undefined", "-fno-omit-frame-pointer"]
sources = ["Sources/Search/NVFZF.c", "ThirdParty/fzf-native/fzf.c", "ThirdParty/fzf-native/utf8proc-2.10.0/utf8proc.c",
           "Sources/Search/NVSearchQuery.m", "Sources/Search/NVSearchCorpus.m", "Sources/Search/NVSearchService.m",
           "Sources/Browser/NVBrowserSession.m", "Tests/FuzzySearch/Review/round-1/contrarian-ui/probe.m"]
objects = []
for i, source in enumerate(sources):
    obj = out / f"{i}.o"
    language = ["-fblocks", "-fno-objc-arc", "-Wno-deprecated-declarations", "-Wno-incomplete-implementation",
                "-Wno-protocol", "-include", str(ROOT / "Config/Notation_Prefix.pch")] if source.endswith(".m") else ["-std=c11"]
    subprocess.run(["xcrun", "clang", *flags, *language, "-c", str(ROOT / source), "-o", str(obj)], check=True)
    objects.append(str(obj))
exe = out / "browser-tests"
subprocess.run(["xcrun", "clang", *flags, *objects, "-framework", "Cocoa", "-framework", "Carbon", "-o", str(exe)], check=True)
record = {"head": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(), "baseline_inline": a.baseline_inline, "architecture": a.arch or "native", "sanitizers": a.sanitize, "sources": {source: hashlib.sha256((ROOT / source).read_bytes()).hexdigest() for source in sources}, "extracted_methods_sha256": hashlib.sha256((out / "primary-selection.inc").read_bytes()).hexdigest()}
(Path(__file__).parent / ("baseline-source-record.json" if a.baseline_inline else ("fixed-sanitize-source-record.json" if a.sanitize else "fixed-native-source-record.json") if a.expect_inline_preserved else "sanitize-source-record.json" if a.sanitize else "native-source-record.json")).write_text(json.dumps(record, indent=2) + "\n")
result = subprocess.run([str(exe)], capture_output=True, text=True, timeout=90)
print(result.stdout, end="")
print(result.stderr, end="")
if a.expect_inline_preserved and not a.baseline_inline:
    (Path(__file__).parent / ("fixed-sanitize-results.txt" if a.sanitize else "fixed-native-results.txt")).write_text(result.stdout + result.stderr)
raise SystemExit(result.returncode)
