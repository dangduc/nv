#!/usr/bin/env python3
"""Exercise new intent replacement and nested publication cases in production methods."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

suite = Path(__file__).resolve().parent
repo = suite.parents[3]
sys.path.insert(0, str(repo / "Tests"))
from compiler_support import include_flags

out = repo / "build/TypingReview/round3/ousterhout"
out.mkdir(parents=True, exist_ok=True)

def method(source, prefix):
    start = source.index(prefix)
    return source[start:source.index("\n}\n", start) + 3]

controller = (repo / "Sources/Application/NVApplicationController.m").read_text()
search = (repo / "Sources/Browser/AppController.m").read_text()
multiple = (repo / "Sources/Browser/AppController_MultipleWindows.m").read_text()
coordinator_prefixes = ["- (NVSearchNoteSnapshot *)searchSnapshotForNote:", "- (void)invalidateBrowserSearches {", "- (void)searchableNoteDidChange:", "- (NVNoteEditingSession *)editingSessionForNote:", "- (void)refreshBrowsers {", "- (void)scheduleBrowserRefresh {", "- (void)noteMetadataUpdated:", "- (void)titleUpdatedForNote:", "- (void)contentsUpdatedForNote:", "- (void)noteEditorChanged:"]
(out / "coordinator.inc").write_text("\n".join(method(controller, prefix) for prefix in coordinator_prefixes))
(out / "browser.inc").write_text(method(search, "- (void)textDidChange:") + method(multiple, "- (void)refreshEditorForNote:") + method(search, "- (void)titleUpdatedForNote:"))
strings = (repo / "Sources/Utilities/NSString_NV.m").read_text()
(out / "uuid.inc").write_text(method(strings, "+ (NSString*)uuidStringWithBytes:"))
flags = ["-g", "-O1", "-arch", "x86_64", "-DUTF8PROC_STATIC",
         "-I" + str(out), "-I" + str(repo / "ThirdParty/fzf-native"), *include_flags(repo)]
sources = ["Sources/Search/NVFZF.c", "ThirdParty/fzf-native/fzf.c",
           "ThirdParty/fzf-native/utf8proc-2.10.0/utf8proc.c", "Sources/Search/NVSearchQuery.m",
           "Sources/Search/NVSearchCorpus.m", "Sources/Search/NVSearchService.m",
           "Sources/Browser/NVBrowserSession.m", str(suite / "probe.m")]
objects, compile_logs = [], []
for index, source in enumerate(sources):
    obj = out / f"{index}.o"
    language = ["-fblocks", "-fno-objc-arc", "-Wno-deprecated-declarations",
                "-Wno-incomplete-implementation", "-Wno-protocol", "-include",
                str(repo / "Config/Notation_Prefix.pch")] if source.endswith(".m") else ["-std=c11"]
    command = ["xcrun", "clang", *flags, *language, "-c", str(repo / source), "-o", str(obj)]
    result = subprocess.run(command, capture_output=True, text=True, timeout=60)
    compile_logs.append(result.stdout + result.stderr)
    if result.returncode:
        (out / "compile.log").write_text("".join(compile_logs))
        raise SystemExit(result.stderr)
    objects.append(str(obj))
command = ["xcrun", "clang", *flags, *objects, "-framework", "Cocoa", "-framework", "Carbon", "-o", str(out / "probe")]
result = subprocess.run(command, capture_output=True, text=True, timeout=30)
compile_logs.append(result.stdout + result.stderr)
(out / "compile.log").write_text("".join(compile_logs))
if result.returncode:
    raise SystemExit(result.stderr)
result = subprocess.run([str(out / "probe")], capture_output=True, text=True, timeout=30)
(suite / "output.txt").write_text(result.stdout + result.stderr)
report = {"head": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip(),
          "command": "python3 Tests/TypingReview/round3/ousterhout/run.py",
          "application_controller_sha256": hashlib.sha256(controller.encode()).hexdigest(),
          "browser_controller_sha256": hashlib.sha256(search.encode()).hexdigest(),
          "multiple_windows_sha256": hashlib.sha256(multiple.encode()).hexdigest(),
          "native_exit": result.returncode, "passed": result.returncode == 0 and "PASS: refresh ownership review" in result.stdout}
(suite / "results.json").write_text(json.dumps(report, indent=2) + "\n")
print(result.stdout, end="")
print(result.stderr, end="")
raise SystemExit(0 if report["passed"] else 1)
