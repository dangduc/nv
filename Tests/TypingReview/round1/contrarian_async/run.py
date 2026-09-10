#!/usr/bin/env python3
"""Review shared-worker pressure using real production analysis scheduling."""
from pathlib import Path
import subprocess

suite = Path(__file__).resolve().parent
repo = suite.parents[3]
out = repo / "build/TypingReview/round1/contrarian_async"
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
command = ["xcrun", "clang", "-arch", "x86_64", "-mmacosx-version-min=10.13",
    "-fblocks", "-fno-objc-arc", "-Wall", "-Wextra", "-Wno-unused-parameter",
    "-Wno-deprecated-declarations", "-Wno-incomplete-implementation",
    "-I", str(repo / "Sources/Editor"), "-framework", "Cocoa", "-framework", "CoreServices",
    str(out / "links.m"), str(repo / "Sources/Editor/NVSourceAnalysis.m"),
    str(suite / "probe.m"), "-o", str(out / "probe")]
subprocess.run(command, check=True)
result = subprocess.run([str(out / "probe")], capture_output=True, text=True, timeout=40)
report = result.stdout + result.stderr
print(result.stdout, end="")
print(result.stderr, end="")
if result.returncode:
    (suite / "output.txt").write_text(report)
    raise SystemExit(result.returncode)

# Each mutation changes only the compiled copy. The expected failed assertion
# proves that the harness observes cancellation, rather than merely completion.
implementation = repo / "Sources/Editor/NVSourceAnalysis.m"
mutations = [
    ("publish-canceled", "BOOL accepted = !atomic_load(&completed->cancelled);",
     "BOOL accepted = YES;", "only the latest requested generation publishes"),
    ("run-canceled-links", '!atomic_load(&job->cancelled) && [snapshot[@"links"] boolValue]',
     '[snapshot[@"links"] boolValue]', "canceled queued snapshots skip link analysis"),
]
for name, old, new, expected in mutations:
    original = implementation.read_text()
    assert original.count(old) == 1
    mutant = out / (name + ".m")
    mutant.write_text(original.replace(old, new))
    binary = out / name
    compile_mutant = [str(mutant) if value == str(implementation) else value for value in command]
    compile_mutant[-1] = str(binary)
    subprocess.run(compile_mutant, check=True)
    failure = subprocess.run([str(binary)], capture_output=True, text=True, timeout=40)
    assert failure.returncode and expected in failure.stderr, failure.stdout + failure.stderr
    message = f"PASS: negative control {name} triggers: {failure.stderr.strip()}\n"
    report += message
    print(message, end="")
(suite / "output.txt").write_text(report)
