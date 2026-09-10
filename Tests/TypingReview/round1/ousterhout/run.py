#!/usr/bin/env python3
"""Headless review of source-analysis/session subscriber interleavings.

The session methods and link decorator are extracted unchanged from production.
Only the unrelated syntax-highlighter dependency is renamed to a no-op fixture.
"""
from pathlib import Path
import subprocess

suite = Path(__file__).resolve().parent
repo = suite.parents[3]
out = suite / "generated"
out.mkdir(exist_ok=True)

links = (repo / "Sources/Editor/AttributedPlainText.m").read_text()
links = links[links.index("- (void)addLinkAttributesForRange:"):
              links.index("- (void)addStrikethroughNearDoneTagsForRange:")]
strings = (repo / "Sources/Utilities/NSString_NV.m").read_text()
escape = strings[strings.index("- (NSString*)stringWithPercentEscapes {"):
                 strings.index("+ (NSString*)reasonStringFromCarbonFSError:")]
(out / "links.m").write_text('''#import <Cocoa/Cocoa.h>
#import <CoreServices/CoreServices.h>
#import "AttributedPlainText.h"
@interface NSString (ReviewEscape)
- (NSString *)stringWithPercentEscapes;
@end
@implementation NSString (ReviewEscape)
''' + escape + '''\n@end
static BOOL _StringWithRangeIsProbablyObjC(NSString *string, NSRange range);
@implementation NSMutableAttributedString (AttributedPlainText)
''' + links + "\n@end\n")

session = (repo / "Sources/Editor/NVNoteEditingSession.m").read_text()
session = session[session.index("- (void)sourceCharactersChanged:"):
                  session.index("- (BOOL)hasMarkedText {")]
(out / "session.inc").write_text(session.replace("NVSourceHighlighter", "ReviewHighlighter"))
command = ["xcrun", "clang", "-arch", "x86_64", "-mmacosx-version-min=10.13",
           "-fblocks", "-fno-objc-arc", "-Wall", "-Wextra", "-Wno-unused-parameter",
           "-Wno-deprecated-declarations", "-Wno-incomplete-implementation",
           "-I", str(repo / "Sources/Editor"), "-I", str(out),
           "-framework", "Cocoa", "-framework", "CoreServices",
           str(out / "links.m"), str(repo / "Sources/Editor/NVSourceAnalysis.m"),
           str(suite / "probe.m"), "-o", str(out / "probe")]
subprocess.run(command, check=True)
result = subprocess.run([str(out / "probe")], capture_output=True, text=True, timeout=30)
(suite / "output.txt").write_text(result.stdout + result.stderr)
print(result.stdout, end="")
print(result.stderr, end="")
raise SystemExit(result.returncode)
