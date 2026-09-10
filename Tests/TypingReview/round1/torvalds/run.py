#!/usr/bin/env python3
"""Bounded headless production source-analysis lifetime and range probe."""
from pathlib import Path
import json
import os
import subprocess

suite = Path(__file__).resolve().parent
repo = suite.parents[3]
out = suite / "artifacts"
out.mkdir(exist_ok=True)
source = (repo / "Sources/Editor/AttributedPlainText.m").read_text()
methods = source[source.index("- (void)addLinkAttributesForRange:"):
                 source.index("- (void)addStrikethroughNearDoneTagsForRange:")]
strings = (repo / "Sources/Utilities/NSString_NV.m").read_text()
escape = strings[strings.index("- (NSString*)stringWithPercentEscapes {"):
                 strings.index("+ (NSString*)reasonStringFromCarbonFSError:")]
category = '''#import <Cocoa/Cocoa.h>
#import <CoreServices/CoreServices.h>
#import "AttributedPlainText.h"
@interface NSString (ProbeEscape)
- (NSString *)stringWithPercentEscapes;
@end
@implementation NSString (ProbeEscape)
''' + escape + '''
@end
static BOOL _StringWithRangeIsProbablyObjC(NSString *string, NSRange range);
@implementation NSMutableAttributedString (AttributedPlainText)
''' + methods + "\n@end\n"
(out / "links.m").write_text(category)
cmd = ["xcrun", "clang", "-arch", "x86_64", "-mmacosx-version-min=10.13",
       "-fblocks", "-fno-objc-arc", "-g", "-O1", "-fsanitize=address,undefined",
       "-fno-omit-frame-pointer", "-Wno-deprecated-declarations",
       "-Wno-incomplete-implementation", "-I", str(repo / "Sources/Editor"),
       "-framework", "Cocoa", "-framework", "CoreServices",
       str(out / "links.m"), str(repo / "Sources/Editor/NVSourceAnalysis.m"),
       str(suite / "probe.m"), "-o", str(out / "probe")]
build = subprocess.run(cmd, capture_output=True, text=True, timeout=45)
(out / "compile.log").write_text(build.stdout + build.stderr)
if build.returncode:
    raise SystemExit(build.stderr)
result = subprocess.run([str(out / "probe")], capture_output=True, text=True, timeout=45,
                        env=dict(os.environ, ASAN_OPTIONS="detect_leaks=0:halt_on_error=1",
                                 UBSAN_OPTIONS="halt_on_error=1:print_stacktrace=1"))
(out / "output.txt").write_text(result.stdout + result.stderr)
report = {"head": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip(),
          "command": "python3 Tests/TypingReview/round1/torvalds/run.py",
          "sanitizers": ["address", "undefined"], "native_exit": result.returncode,
          "passed": result.returncode == 0 and "PASS: all review probes" in result.stdout}
(out / "results.json").write_text(json.dumps(report, indent=2) + "\n")
print(result.stdout, end="")
print(result.stderr, end="")
raise SystemExit(0 if report["passed"] else 1)
