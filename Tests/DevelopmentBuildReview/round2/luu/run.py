#!/usr/bin/env python3
"""Compare frozen wiki-link scans in disposable Cocoa bundles, without a GUI."""
from pathlib import Path
import json
import plistlib
import shutil
import statistics
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[4]
OUT = Path(__file__).resolve().parent
REFS = {"base": "bd74bf3", "buggy": "2dbfd46", "fixed": "3a3dc4f"}


def source(ref, path):
    return subprocess.check_output(["git", "show", f"{ref}:{path}"], cwd=ROOT, text=True)


def scan(text):
    start = text.index("- (void)_addDoubleBracketedNVLinkAttributesForRange:")
    return text[start:text.index("\nstatic BOOL _StringWithRangeIsProbablyObjC", start)]


def helper(text):
    start = text.index("\nstatic BOOL _StringWithRangeIsProbablyObjC", text.index("- (void)_addDoubleBracketedNVLinkAttributesForRange:"))
    return text[start:text.index("- (void)addStrikethroughNearDoneTagsForRange:", start)]


def escape(text):
    return text[text.index("- (NSString*)stringWithPercentEscapes {"):text.index("+ (NSString*)reasonStringFromCarbonFSError:")]


scans = {mode: source(ref, "Sources/Editor/AttributedPlainText.m") for mode, ref in REFS.items()}
escapes = {mode: escape(source(ref, "Sources/Utilities/NSString_NV.m")) for mode, ref in REFS.items()}
assert len(set(escapes.values())) == 1, "Percent-escape source changed between revisions"
assert len({helper(text) for text in scans.values()}) == 1, "Scan helper source changed between revisions"
identity = source(REFS["fixed"], "Sources/Application/NVAppIdentity.h")
assert identity == source(REFS["buggy"], "Sources/Application/NVAppIdentity.h"), "Identity helper changed"

code = '#import <Cocoa/Cocoa.h>\n#import <time.h>\n' + identity + r'''
@interface NSString (BenchEscape)
- (NSString *)stringWithPercentEscapes;
@end
@implementation NSString (BenchEscape)
''' + escapes["fixed"] + r'''
@end
static BOOL _StringWithRangeIsProbablyObjC(NSString *, NSRange);
@interface NSMutableAttributedString (Bench)
- (void)baseScan:(NSRange)range;
- (void)buggyScan:(NSRange)range;
- (void)fixedScan:(NSRange)range;
@end
@implementation NSMutableAttributedString (Bench)
''' + "\n".join(scan(text).replace("_addDoubleBracketedNVLinkAttributesForRange:", mode + "Scan:") for mode, text in scans.items()) + '\n@end\n' + helper(scans["fixed"]) + r'''
static double now(void) {
    struct timespec time;
    clock_gettime(CLOCK_MONOTONIC, &time);
    return time.tv_sec + time.tv_nsec / 1e9;
}
static void runScan(NSMutableAttributedString *text, int mode) {
    NSRange range = NSMakeRange(0, text.length);
    if (mode == 0) [text baseScan:range];
    else if (mode == 1) [text buggyScan:range];
    else [text fixedScan:range];
}
static NSArray *snapshot(NSAttributedString *text, NSString *expectedScheme) {
    NSMutableArray *links = [NSMutableArray array];
    [text enumerateAttribute:NSLinkAttributeName inRange:NSMakeRange(0, text.length) options:0
        usingBlock:^(NSURL *url, NSRange range, BOOL *stop) {
            if (!url) return;
            if (![url.scheme isEqualToString:expectedScheme]) {
                fprintf(stderr, "Unexpected scheme: %s\n", url.absoluteString.UTF8String);
                exit(1);
            }
            NSString *suffix = [url.absoluteString substringFromIndex:expectedScheme.length];
            [links addObject:@[NSStringFromRange(range), suffix]];
        }];
    return links;
}
int main(void) {
    @autoreleasepool {
        const char *modes[] = {"base", "buggy", "fixed"};
        printf("flavor=%s scheme=%s\n", [[[[NSBundle mainBundle] infoDictionary] objectForKey:@"NVBuildFlavor"] UTF8String], NVNoteURLScheme().UTF8String);
        int sizes[] = {0, 10, 1000, 10000};
        int batches[] = {200, 10, 1, 1};
        NSUInteger checkedScans = 0, checkedLinks = 0;
        for (int size = 0; size < 4; size++) {
            NSMutableString *input = [NSMutableString string];
            for (int i = 0; i < sizes[size]; i++) [input appendFormat:@"[[Note %d]] body text\n", i];
            if (!sizes[size]) [input appendString:@"No links in this ordinary note."];
            for (int rep = 0; rep < 13; rep++) {
                NSArray *reference = nil;
                for (int order = 0; order < 3; order++) {
                    int mode = (order + rep) % 3;
                    @autoreleasepool {
                        NSMutableArray *texts = [NSMutableArray array];
                        for (int i = 0; i < batches[size]; i++) {
                            [texts addObject:[[[NSMutableAttributedString alloc] initWithString:input] autorelease]];
                        }
                        double start = now();
                        for (NSMutableAttributedString *text in texts) runScan(text, mode);
                        double elapsed = (now() - start) * 1000 / batches[size];
                        for (NSMutableAttributedString *text in texts) {
                            NSArray *actual = snapshot(text, mode ? NVNoteURLScheme() : @"nvalt");
                            if (actual.count != sizes[size]) {
                                fprintf(stderr, "Link count mismatch\n");
                                return 1;
                            }
                            if (!reference) reference = [actual copy];
                            if (![reference isEqualToArray:actual]) {
                                fprintf(stderr, "URL or range mismatch between revisions\n");
                                return 1;
                            }
                            checkedScans++;
                            checkedLinks += actual.count;
                        }
                        printf("scan,%d,%d,%s,%d,%.9f\n", sizes[size], rep, modes[mode], batches[size], elapsed);
                    }
                }
                [reference release];
            }
        }
        NSArray *cases = @[@"[[A & B]] [[café/雪?#]] [[100%]]", @"[[Note]] [[Other]] [[Note]]",
            @"[[unfinished", @"[[]] [[ spaced ]]", @"[[object alloc] init] [[Good title]]"];
        for (NSString *input in cases) {
            NSArray *reference = nil;
            for (int mode = 0; mode < 3; mode++) {
                NSMutableAttributedString *text = [[[NSMutableAttributedString alloc] initWithString:input] autorelease];
                runScan(text, mode);
                NSArray *actual = snapshot(text, mode ? NVNoteURLScheme() : @"nvalt");
                if (!reference) reference = [actual copy];
                if (![reference isEqualToArray:actual]) {
                    fprintf(stderr, "Semantic fixture mismatch\n");
                    return 1;
                }
                checkedScans++;
                checkedLinks += actual.count;
            }
            [reference release];
        }
        printf("PASS,scans,%lu,links,%lu,semantic_cases,%lu\n", (unsigned long)checkedScans, (unsigned long)checkedLinks, (unsigned long)cases.count);
    }
    return 0;
}
'''

report = {
    "refs": {mode: subprocess.check_output(["git", "rev-parse", ref], cwd=ROOT, text=True).strip() for mode, ref in REFS.items()},
    "environment": subprocess.check_output(["sw_vers"], text=True).strip(),
    "xcode": subprocess.check_output(["xcodebuild", "-version"], text=True).strip(),
    "host_architecture": subprocess.check_output(["uname", "-m"], text=True).strip(),
    "executable_architecture": "x86_64",
    "method": {"repetitions": 13, "discarded_initial_repetitions": 1, "rotation": "(order + repetition) % 3", "batches_by_size": {"0": 200, "10": 10, "1000": 1, "10000": 1}, "shared_dependencies_identical": True, "helper_microbenchmark": "omitted; helper source unchanged"},
    "flavors": {},
}
with tempfile.TemporaryDirectory(prefix="nvalt-round2-luu-") as temp:
    temp = Path(temp)
    (temp / "probe.m").write_text(code)
    compile_command = ["xcrun", "clang", "-arch", "x86_64", "-O2", "-fno-objc-arc", "-fblocks", "-Wno-deprecated-declarations", "-framework", "Cocoa", "-framework", "CoreServices", str(temp / "probe.m"), "-o", str(temp / "probe")]
    subprocess.run(compile_command, check=True)
    report["compiler_flags"] = compile_command[2:-3]
    for flavor in ["development", "release"]:
        app = temp / (flavor + ".app")
        executable = app / "Contents/MacOS/probe"
        executable.parent.mkdir(parents=True)
        shutil.copy2(temp / "probe", executable)
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps({"CFBundleExecutable": "probe", "CFBundleIdentifier": "org.nvalt.round2.luu." + flavor, "CFBundlePackageType": "APPL", "NVBuildFlavor": flavor}))
        output = subprocess.check_output([str(executable)], text=True)
        (OUT / (flavor + "-raw.txt")).write_text(output)
        measurements = {}
        for line in output.splitlines():
            parts = line.split(",")
            if parts[0] == "scan" and int(parts[2]) > 0:
                measurements.setdefault(parts[1], {}).setdefault(parts[3], []).append(float(parts[5]))
        assert output.splitlines()[-1].startswith("PASS,"), output
        flavor_report = {"identity": output.splitlines()[0], "behavior_checks": output.splitlines()[-1], "scans": {}}
        for size, modes in measurements.items():
            median = {mode: statistics.median(values) for mode, values in modes.items()}
            flavor_report["scans"][size] = {"median_ms": median, "min_ms": {mode: min(values) for mode, values in modes.items()}, "max_ms": {mode: max(values) for mode, values in modes.items()}, "fixed_to_base_ratio": median["fixed"] / median["base"], "buggy_to_base_ratio": median["buggy"] / median["base"], "fixed_minus_base_ms": median["fixed"] - median["base"], "saved_vs_buggy_ms": median["buggy"] - median["fixed"]}
        report["flavors"][flavor] = flavor_report
(OUT / "results.json").write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps(report, indent=2))
print("PASS: all three revisions produced equal link ranges and URL suffixes, with the expected scheme for each flavor and revision")
