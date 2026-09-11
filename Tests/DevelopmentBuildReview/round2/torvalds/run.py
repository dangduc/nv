#!/usr/bin/env python3
"""Compare frozen production wiki scans without a GUI, preferences, or user files."""
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
CURRENT = "3a3dc4fb7194b5ea7189295a7bbd17393bb32038"
PREVIOUS = "2dbfd4621077d6dec8b1195cb5002e29179cdfaa"
BASE = "bd74bf3e9e655fc69b5724fb7638f23a2f971f54"
OUT = REPO / "build/DevelopmentBuildReview/round2/torvalds"
OUT.mkdir(parents=True, exist_ok=True)

def frozen(ref, path):
    return subprocess.check_output(["git", "show", f"{ref}:{path}"], cwd=REPO, text=True, timeout=15)

def scan(source):
    start = source.index("- (void)_addDoubleBracketedNVLinkAttributesForRange:")
    return source[start:source.index("\nstatic BOOL _StringWithRangeIsProbablyObjC", start)]

path = "Sources/Editor/AttributedPlainText.m"
current = frozen(CURRENT, path)
assert (REPO / path).read_text() == current
identity = "Sources/Application/NVAppIdentity.h"
assert (REPO / identity).read_text() == frozen(CURRENT, identity)
helper_start = current.index("\nstatic BOOL _StringWithRangeIsProbablyObjC", current.index("- (void)_addDoubleBracketedNVLinkAttributesForRange:"))
helper = current[helper_start:current.index("- (void)addStrikethroughNearDoneTagsForRange:", helper_start)]
strings = frozen(CURRENT, "Sources/Utilities/NSString_NV.m")
assert (REPO / "Sources/Utilities/NSString_NV.m").read_text() == strings
escape = strings[strings.index("- (NSString*)stringWithPercentEscapes {"):strings.index("+ (NSString*)reasonStringFromCarbonFSError:")]
generated = '#import <Cocoa/Cocoa.h>\n#import "NVAppIdentity.h"\n' + '''
static NSUInteger SchemeCalls;
static NSString *ObservedScheme(void) { SchemeCalls++; return NVNoteURLScheme(); }
@interface NSString (ReviewEscape)
- (NSString *)stringWithPercentEscapes;
@end
@implementation NSString (ReviewEscape)
''' + escape + '\n@end\n' + '''
static BOOL _StringWithRangeIsProbablyObjC(NSString *, NSRange);
@interface NSMutableAttributedString (ReviewScan)
- (void)baselineScan:(NSRange)range;
- (void)previousScan:(NSRange)range;
- (void)currentScan:(NSRange)range;
@end
#define NVNoteURLScheme() ObservedScheme()
@implementation NSMutableAttributedString (ReviewScan)
'''
for ref, name in [(BASE, "baselineScan:"), (PREVIOUS, "previousScan:"), (CURRENT, "currentScan:")]:
    generated += scan(frozen(ref, path)).replace("_addDoubleBracketedNVLinkAttributesForRange:", name)
generated += '\n@end\n#undef NVNoteURLScheme\n' + helper
(OUT / "production.inc").write_text(generated)
summary = {"reviewedCommit": CURRENT, "previousCommit": PREVIOUS, "baselineCommit": BASE,
           "macOS": subprocess.check_output(["sw_vers"], text=True), "xcode": subprocess.check_output(["xcodebuild", "-version"], text=True),
           "productionHashes": {path: hashlib.sha256(current.encode()).hexdigest(), identity: hashlib.sha256((REPO / identity).read_bytes()).hexdigest(), "Sources/Utilities/NSString_NV.m": hashlib.sha256(strings.encode()).hexdigest()}, "runs": []}
with tempfile.TemporaryDirectory(prefix="nvalt-wiki-review-") as temporary:
    root = Path(temporary)
    for arch in ["arm64", "x86_64"]:
        binary = OUT / f"probe-{arch}"
        subprocess.run(["xcrun", "clang", "-arch", arch, "-O2", "-fno-objc-arc", "-fblocks", "-Wall", "-Wextra", "-Wno-unused-parameter", "-Wno-deprecated-declarations",
                        "-framework", "Cocoa", "-framework", "CoreServices", "-I", str(OUT), "-I", str(REPO / "Sources/Application"), str(HERE / "probe.m"), "-o", str(binary)], check=True, timeout=45)
        for label, flavor, identifier in [("development", "development", "net.elasticthreads.nv.development"),
                                           ("copied-development", "development", "org.nvalt.review.copied"),
                                           ("release", "release", "net.elasticthreads.nv"),
                                           ("missing-flavor", None, "org.nvalt.review.missing")]:
            app = root / f"{arch}-{label}.app"
            executable = app / "Contents/MacOS/probe"
            executable.parent.mkdir(parents=True)
            shutil.copy2(binary, executable)
            metadata = {"CFBundleExecutable": "probe", "CFBundleIdentifier": identifier, "CFBundlePackageType": "APPL"}
            if flavor is not None:
                metadata["NVBuildFlavor"] = flavor
            (app / "Contents/Info.plist").write_bytes(plistlib.dumps(metadata))
            result = OUT / f"{arch}-{label}.json"
            run = subprocess.run(["arch", f"-{arch}", str(executable), str(result), "development" if flavor == "development" else "release"], capture_output=True, text=True, timeout=45)
            (OUT / f"{arch}-{label}.log").write_text(run.stdout + run.stderr)
            print(f"{arch} {label}: {run.stdout}{run.stderr}", end="", flush=True)
            run.check_returncode()
            summary["runs"].append({"architecture": arch, "fixture": label, **json.loads(result.read_text())})
summary["probeHashes"] = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in [HERE / "probe.m", HERE / "run.py"]}
(HERE / "results.json").write_text(json.dumps(summary, indent=2) + "\n")
