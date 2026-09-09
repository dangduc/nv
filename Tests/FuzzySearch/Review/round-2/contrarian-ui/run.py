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
p.add_argument("--arch", choices=["arm64"], default="arm64")
a = p.parse_args()
out = ROOT / "build/FuzzySearchContrarianUIRound2" / ("sanitize" if a.sanitize else a.arch or "native")
out.mkdir(parents=True, exist_ok=True)
table_source = (ROOT / "Sources/UI/NotesTableView.m").read_text()
selection_methods = []
for prefix in ["- (BOOL)searchRowsAreAvailable", "- (NSInteger)primarySelectedRow", "- (void)setPrimarySelectedRow:",
               "- (void)preparePrimarySelectionForRow:", "- (void)notifyPrimaryChangeFromKey:", "- (void)selectRowIndexes:",
               "- (void)selectRowAndScroll:", "- (void)keyDown:", "- (NSMenu *)menuForEvent:",
               "- (void)clearInlineEditTarget", "- (NoteObject *)noteForInlineEditAtRow:", "- (BOOL)hasInlineEditTarget",
               "- (void)editColumn:", "- (void)textDidEndEditing:", "- (BOOL)abortEditing"]:
    active_source = table_source
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
start = controller_source.index("- (IBAction)deleteNote:")
(out / "delete-note.inc").write_text(controller_source[start:controller_source.index("\n}", start)+2])
flags = ["-g", "-O1" if a.sanitize else "-O2", "-DUTF8PROC_STATIC", "-I" + str(out), "-I" + str(ROOT / "ThirdParty/fzf-native"), *include_flags(ROOT)]
if a.arch:
    flags += ["-arch", a.arch]
if a.sanitize:
    flags += ["-fsanitize=address,undefined", "-fno-omit-frame-pointer"]
sources = ["Sources/Search/NVFZF.c", "ThirdParty/fzf-native/fzf.c", "ThirdParty/fzf-native/utf8proc-2.10.0/utf8proc.c",
           "Sources/Search/NVSearchQuery.m", "Sources/Search/NVSearchCorpus.m", "Sources/Search/NVSearchService.m",
           "Sources/Browser/NVBrowserSession.m", "Tests/FuzzySearch/Review/round-2/contrarian-ui/probe.m"]
reviewed_sources = sources + ["Sources/UI/NotesTableView.m", "Sources/Browser/AppController.m", "Sources/Editor/TagEditingManager.m"]
input_hashes = {source: hashlib.sha256((ROOT / source).read_bytes()).hexdigest() for source in reviewed_sources}
objects = []
for i, source in enumerate(sources):
    obj = out / f"{i}.o"
    language = ["-fblocks", "-fno-objc-arc", "-Wno-deprecated-declarations", "-Wno-incomplete-implementation",
                "-Wno-protocol", "-include", str(ROOT / "Config/Notation_Prefix.pch")] if source.endswith(".m") else ["-std=c11"]
    subprocess.run(["xcrun", "clang", *flags, *language, "-c", str(ROOT / source), "-o", str(obj)], check=True)
    objects.append(str(obj))
exe = out / "browser-tests"
subprocess.run(["xcrun", "clang", *flags, *objects, "-framework", "Cocoa", "-framework", "Carbon", "-o", str(exe)], check=True)
after_hashes = {source: hashlib.sha256((ROOT / source).read_bytes()).hexdigest() for source in reviewed_sources}
if input_hashes != after_hashes:
    raise SystemExit("Source changed during compilation; discard this run and repeat.")
record = {"head": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(), "architecture": a.arch, "sanitizers": a.sanitize, "sources": input_hashes, "sources_stable_during_compilation": input_hashes == after_hashes, "extracted_methods": {name: hashlib.sha256((out / name).read_bytes()).hexdigest() for name in ["primary-selection.inc", "multi-tag.inc", "delete-note.inc"]}}
prefix = "sanitize" if a.sanitize else "native"
(Path(__file__).parent / (prefix + "-source-record.json")).write_text(json.dumps(record, indent=2) + "\n")
result = subprocess.run([str(exe)], capture_output=True, text=True, timeout=90)
print(result.stdout, end="")
print(result.stderr, end="")
(Path(__file__).parent / (prefix + "-results.txt")).write_text(result.stdout + result.stderr)
raise SystemExit(result.returncode)
