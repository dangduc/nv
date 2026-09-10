#!/usr/bin/env python3
"""Bounded, headless performance probes of exact source-analysis production code."""
from pathlib import Path
import json
import platform
import subprocess

suite = Path(__file__).resolve().parent
repo = suite.parents[3]
out = repo / "build/TypingReview/round1/luu"
out.mkdir(parents=True, exist_ok=True)
source = (repo / "Sources/Editor/AttributedPlainText.m").read_text()
methods = source[source.index("- (void)addLinkAttributesForRange:"):
                 source.index("- (void)addStrikethroughNearDoneTagsForRange:")]
strings = (repo / "Sources/Utilities/NSString_NV.m").read_text()
escape = strings[strings.index("- (NSString*)stringWithPercentEscapes {"):
                 strings.index("+ (NSString*)reasonStringFromCarbonFSError:")]
(out / "links.m").write_text('''#import <Cocoa/Cocoa.h>
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
''' + methods + "\n@end\n")
session = (repo / "Sources/Editor/NVNoteEditingSession.m").read_text()
publication_start = session.index("- (void)sourceAnalysis:(NVSourceAnalysis *)analysis didFinish:")
publication = session[publication_start:session.index("\n- (", publication_start + 1)]
(out / "publication.inc").write_text(publication)
command = ["xcrun", "clang", "-arch", "x86_64", "-mmacosx-version-min=10.13",
    "-O2", "-fblocks", "-fno-objc-arc", "-Wall", "-Wextra", "-Wno-unused-parameter",
    "-Wno-deprecated-declarations", "-Wno-incomplete-implementation",
    "-I", str(repo / "Sources/Editor"), "-I", str(out),
    "-framework", "Cocoa", "-framework", "CoreServices",
    str(out / "links.m"), str(repo / "Sources/Editor/NVSourceAnalysis.m"),
    str(suite / "probe.m"), "-o", str(out / "probe")]
subprocess.run(command, check=True)
result = subprocess.run([str(out / "probe")], capture_output=True, text=True, timeout=110)
(suite / "output.txt").write_text(result.stdout + result.stderr)
(suite / "environment.json").write_text(json.dumps({
    "platform": platform.platform(),
    "head": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip(),
    "compiler": subprocess.check_output(["xcrun", "clang", "--version"], text=True).strip(),
    "command": command, "exit_code": result.returncode,
}, indent=2) + "\n")
print(result.stdout, end="")
print(result.stderr, end="")
raise SystemExit(result.returncode)
