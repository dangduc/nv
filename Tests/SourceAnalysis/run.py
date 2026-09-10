#!/usr/bin/env python3
"""Exercise the production source-analysis worker without opening user notes."""
from pathlib import Path
import subprocess

repo = Path(__file__).resolve().parents[2]
out = repo / "build/SourceAnalysis"
out.mkdir(parents=True, exist_ok=True)

# Compile the production link methods in a small category. The rest of that
# source file contains font/import code that needs the running application.
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
subprocess.run(["xcrun", "clang", "-arch", "x86_64", "-mmacosx-version-min=10.13",
    "-fblocks", "-fno-objc-arc", "-Wall", "-Wextra", "-Wno-unused-parameter",
    "-Wno-deprecated-declarations", "-Wno-incomplete-implementation",
    "-I", str(repo / "Sources/Editor"), "-framework", "Cocoa", "-framework", "CoreServices",
    str(out / "links.m"), str(repo / "Sources/Editor/NVSourceAnalysis.m"),
    str(Path(__file__).parent / "probe.m"), "-o", str(out / "probe")], check=True)
result = subprocess.run([str(out / "probe")], capture_output=True, text=True, timeout=90)
(out / "output.txt").write_text(result.stdout + result.stderr)
print(result.stdout, end="")
print(result.stderr, end="")
raise SystemExit(result.returncode)
