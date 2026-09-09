#!/usr/bin/env python3
"""Exercise production browser occurrences and asynchronous state with real fzf."""
import argparse
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "Tests"))
from compiler_support import include_flags

p = argparse.ArgumentParser()
p.add_argument("--sanitize", action="store_true")
p.add_argument("--arch", choices=["arm64", "x86_64"])
a = p.parse_args()
out = ROOT / "build/FuzzySearchBrowserTests" / ("sanitize" if a.sanitize else a.arch or "native")
out.mkdir(parents=True, exist_ok=True)
table_source = (ROOT / "Sources/UI/NotesTableView.m").read_text()
selection_methods = []
for prefix in ["- (BOOL)searchRowsAreAvailable", "- (NSInteger)primarySelectedRow", "- (void)setPrimarySelectedRow:",
               "- (void)preparePrimarySelectionForRow:", "- (void)notifyPrimaryChangeFromKey:", "- (void)selectRowIndexes:"]:
    start = table_source.index(prefix)
    selection_methods.append(table_source[start:table_source.index("\n}", start) + 2])
(out / "primary-selection.inc").write_text("\n".join(selection_methods))
controller_source = (ROOT / "Sources/Browser/AppController.m").read_text()
tag_methods = []
for prefix in ["- (void)captureMultiTagNotes:", "- (NSArray *)pendingMultiTagNotes", "- (void)cancelMultiTagEditing",
               "- (IBAction)multiTag:", "- (void)releaseTagEditor:"]:
    start = controller_source.index(prefix)
    tag_methods.append(controller_source[start:controller_source.index("\n}", start) + 2])
(out / "multi-tag.inc").write_text("\n".join(tag_methods))
flags = ["-g", "-O1" if a.sanitize else "-O2", "-DUTF8PROC_STATIC", "-I" + str(out), "-I" + str(ROOT / "ThirdParty/fzf-native"), *include_flags(ROOT)]
if a.arch:
    flags += ["-arch", a.arch]
if a.sanitize:
    flags += ["-fsanitize=address,undefined", "-fno-omit-frame-pointer"]
sources = ["Sources/Search/NVFZF.c", "ThirdParty/fzf-native/fzf.c", "ThirdParty/fzf-native/utf8proc-2.10.0/utf8proc.c",
           "Sources/Search/NVSearchQuery.m", "Sources/Search/NVSearchCorpus.m", "Sources/Search/NVSearchService.m",
           "Sources/Browser/NVBrowserSession.m", "Tests/FuzzySearch/Browser/browser-tests.m"]
objects = []
for i, source in enumerate(sources):
    obj = out / f"{i}.o"
    language = ["-fblocks", "-fno-objc-arc", "-Wno-deprecated-declarations", "-Wno-incomplete-implementation",
                "-Wno-protocol", "-include", str(ROOT / "Config/Notation_Prefix.pch")] if source.endswith(".m") else ["-std=c11"]
    subprocess.run(["xcrun", "clang", *flags, *language, "-c", str(ROOT / source), "-o", str(obj)], check=True)
    objects.append(str(obj))
exe = out / "browser-tests"
subprocess.run(["xcrun", "clang", *flags, *objects, "-framework", "Cocoa", "-framework", "Carbon", "-o", str(exe)], check=True)
subprocess.run([str(exe)], check=True, timeout=90)
