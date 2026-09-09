#!/usr/bin/env python3
"""Native duplicate-row tag actions and same-note occurrence review."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[5]
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "Tests"))
from compiler_support import include_flags


def extract(source, prefix):
    start = source.index(prefix)
    # All selected methods end with a brace at the start of its line.
    return source[start:source.index("\n}", start) + 2]


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--sanitize", action="store_true")
parser.add_argument("--negative-controls", action="store_true")
args = parser.parse_args()
out = ROOT / "build/FuzzySearchContrarianUIRound3" / ("sanitize" if args.sanitize else "native")
out.mkdir(parents=True, exist_ok=True)
app = out / "Tag Review.app"
binary = app / "Contents/MacOS/review"
binary.parent.mkdir(parents=True, exist_ok=True)
resources = app / "Contents/Resources"
resources.mkdir(parents=True, exist_ok=True)
(app / "Contents/Info.plist").write_bytes(plistlib.dumps({
    "CFBundleExecutable": "review", "CFBundleIdentifier": "org.nvalt.fuzzy-review.tags",
    "CFBundlePackageType": "APPL", "CFBundleName": "Tag Review", "NSHighResolutionCapable": True,
}))
sources = ["Sources/Search/NVFZF.c", "ThirdParty/fzf-native/fzf.c", "ThirdParty/fzf-native/utf8proc-2.10.0/utf8proc.c",
           "Sources/Search/NVSearchQuery.m", "Sources/Search/NVSearchCorpus.m", "Sources/Search/NVSearchService.m",
           "Sources/Browser/NVBrowserSession.m", "Sources/Editor/TagEditingManager.m",
           "Tests/FuzzySearch/Review/round-3/contrarian-ui/probe.m"]
extra = ["Sources/UI/NotesTableView.m", "Sources/Browser/AppController.m", "Resources/Localization/en.lproj/TagEditingManager.xib"]
extra += [str(path.relative_to(ROOT)) for path in (ROOT / "ThirdParty/fzf-native").rglob("*.h")]
extra += ["ThirdParty/fzf-native/utf8proc-2.10.0/utf8proc_data.c"]
extra += [str(path.relative_to(ROOT)) for path in (ROOT / "Sources/Search").glob("*.h")]
extra += ["Sources/Browser/NVBrowserSession.h", "Sources/Editor/TagEditingManager.h"]
head_at_snapshot = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
inputs = {name: (ROOT / name).read_bytes() for name in sources + extra}
for name, data in inputs.items():
    path = out / "inputs" / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
table = inputs["Sources/UI/NotesTableView.m"].decode()
table_methods = ["- (BOOL)searchRowsAreAvailable", "- (NSInteger)primarySelectedRow", "- (void)setPrimarySelectedRow:",
                 "- (void)preparePrimarySelectionForRow:", "- (void)notifyPrimaryChangeFromKey:", "- (void)selectRowIndexes:",
                 "- (void)selectRowAndScroll:"]
(out / "primary-selection.inc").write_text("\n".join(extract(table, name) for name in table_methods))
controller = inputs["Sources/Browser/AppController.m"].decode()
tag_methods = ["- (IBAction)tagNote:", "- (void)captureMultiTagNotes:", "- (NSArray *)pendingMultiTagNotes",
               "- (void)cancelMultiTagEditing", "- (NSArray *)commonLabelsForNotes:", "- (IBAction)multiTag:", "- (void)releaseTagEditor:"]
tags = "\n".join(extract(controller, name) for name in tag_methods)
display = "\n".join(extract(controller, name) for name in ["- (void)processChangedSelectionForTable:", "- (BOOL)displayContentsForNoteAtIndex:"])
(out / "multi-tag.inc").write_text(tags)
(out / "display.inc").write_text(display)
subprocess.run(["xcrun", "ibtool", "--compile", str(resources / "TagEditingManager.nib"),
                str(out / "inputs/Resources/Localization/en.lproj/TagEditingManager.xib")], check=True, capture_output=True)
flags = ["-arch", "arm64", "-g", "-O1" if args.sanitize else "-O2", "-DUTF8PROC_STATIC",
         "-I" + str(out), "-I" + str(ROOT / "ThirdParty/fzf-native"), *include_flags(ROOT)]
if args.sanitize:
    flags += ["-fsanitize=address,undefined", "-fno-omit-frame-pointer"]


def compile_probe():
    objects = []
    log = []
    for i, source in enumerate(sources):
        obj = out / f"{i}.o"
        language = ["-fblocks", "-fno-objc-arc", "-Wno-deprecated-declarations", "-Wno-incomplete-implementation",
                    "-Wno-protocol", "-include", str(ROOT / "Config/Notation_Prefix.pch")] if source.endswith(".m") else ["-std=c11"]
        result = subprocess.run(["xcrun", "clang", *flags, *language, "-c", str(out / "inputs" / source), "-o", str(obj)], capture_output=True, text=True)
        log.append(result.stdout + result.stderr)
        if result.returncode:
            print(log[-1]); result.check_returncode()
        objects.append(str(obj))
    result = subprocess.run(["xcrun", "clang", *flags, *objects, "-framework", "Cocoa", "-framework", "Carbon", "-o", str(binary)], capture_output=True, text=True)
    log.append(result.stdout + result.stderr)
    (out / "compile.log").write_text("".join(log))
    if result.returncode:
        print(log[-1]); result.check_returncode()


def execute(name):
    result = subprocess.run([str(binary)], text=True, capture_output=True, timeout=60)
    (out / (name + ".txt")).write_text(result.stdout + result.stderr)
    print(result.stdout + result.stderr, end="")
    return result


compile_probe()
result = execute("results")
record = {"head_at_snapshot": head_at_snapshot,
          "architecture": "arm64", "sanitizers": args.sanitize, "compiled_from_copied_inputs": True,
          "sources": {name: hashlib.sha256(data).hexdigest() for name, data in inputs.items()},
          "methods": {name: hashlib.sha256((out / name).read_bytes()).hexdigest()
                      for name in ["primary-selection.inc", "multi-tag.inc", "display.inc"]}}
prefix = "sanitize" if args.sanitize else "native"
(HERE / (prefix + "-source-record.json")).write_text(json.dumps(record, indent=2) + "\n")
(HERE / (prefix + "-results.txt")).write_text(result.stdout + result.stderr)
result.check_returncode()
if args.negative_controls:
    browser = inputs["Sources/Browser/NVBrowserSession.m"].decode()
    browser_path = "inputs/Sources/Browser/NVBrowserSession.m"
    controls = [("no-action-dedup", browser_path, browser, browser.replace("if (![seen containsObject:uuid])", "if (YES)"), "two occurrences of one note select the single-note header"),
                ("no-library-guard", "multi-tag.inc", tags, tags.replace(" || multiTagLibrary != [self sharedNotationController]", ""), "replacement library rejects delayed tags"),
                ("same-note-reattach", "display.inc", display, display.replace("if (note != currentNote)", "if (YES)"), "same-note occurrence never enters editor attachment")]
    for name, include, normal, mutation, expected in controls:
        assert mutation != normal
        try:
            (out / include).write_text(mutation)
            compile_probe()
            rejected = execute(name)
            assert rejected.returncode != 0 and expected in rejected.stderr, name
            print("PASS: rejected " + name)
        finally:
            (out / include).write_text(normal)
    compile_probe()
