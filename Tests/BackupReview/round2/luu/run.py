#!/usr/bin/env python3
"""Native probes of production backup files. No shipping application is opened."""
from pathlib import Path
import argparse
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument("--settings-only", action="store_true")
args = parser.parse_args()
includes = [flag for folder in sorted({p.parent for p in (ROOT / "Sources").rglob("*.h")}) for flag in ("-I", str(folder))]
with tempfile.TemporaryDirectory(prefix="nvalt-r2-luu-", dir=ROOT / "build") as temporary:
    temp = Path(temporary).resolve()
    common = ["xcrun", "clang", "-arch", "arm64", "-fno-objc-arc", "-fblocks", "-O1", "-Wno-deprecated-declarations", "-Wno-incomplete-implementation", "-mmacosx-version-min=11.0", "-DNVBACKUPSTORE_TESTING", *includes, "-I", str(ROOT)]
    fixture = (ROOT / "Tests/BackupCoordinator/coordinator.m").read_text()
    prefix = fixture.split("@implementation NVBackupStore")[0]
    prefix = prefix.replace('@"generation":@(generation), @"libraryIdentifier":', '@"encrypted":@NO, @"generation":@(generation), @"libraryIdentifier":')
    helpers = fixture[fixture.index("@implementation NVBackupArchive"):fixture.index("static void RetentionChecks(")]
    settings = temp / "settings.m"
    settings.write_text(prefix + helpers + (HERE / "settings-main.inc").read_text())
    for name, flags in (("ordinary", []), ("fast-math", ["-ffast-math"])):
        binary = temp / name
        subprocess.run([*common, *flags, str(settings), str(ROOT / "Sources/Storage/NVBackupController.m"), str(ROOT / "Sources/Storage/NVBackupStore.m"), "-framework", "Cocoa", "-framework", "CoreServices", "-o", str(binary)], check=True)
        result = subprocess.run([str(binary), str(temp / (name + "-data"))], timeout=30)
        print(f"SETTINGS_BUILD mode={name} exit={result.returncode}", flush=True)
        if result.returncode:
            raise SystemExit(result.returncode)
    if args.settings_only:
        raise SystemExit(0)
    frequency = temp / "frequency.m"
    large_prefix = prefix.replace('#import <Cocoa/Cocoa.h>', '#import <Cocoa/Cocoa.h>\nstatic NSData *ReviewArchiveData;')
    small_data = '[[NSString stringWithFormat:@"generation-%lu", (unsigned long)generation] dataUsingEncoding:NSUTF8StringEncoding]'
    assert small_data in large_prefix
    large_prefix = large_prefix.replace(small_data, 'ReviewArchiveData')
    frequency.write_text(large_prefix + helpers + (HERE / "frequency-main.inc").read_text())
    subprocess.run([*common, str(frequency), str(ROOT / "Sources/Storage/NVBackupController.m"), str(HERE / "measured-store.m"), "-framework", "Cocoa", "-framework", "CoreServices", "-o", str(temp / "frequency")], check=True)
    subprocess.run([str(temp / "frequency"), str(temp / "frequency-data")], check=True, timeout=30)
    subprocess.run([*common, str(HERE / "memory.m"), str(HERE / "measured-store.m"), "-framework", "Foundation", "-o", str(temp / "memory")], check=True)
    peaks = []
    for count in (8, 48):
        output = subprocess.check_output([str(temp / "memory"), str(temp / f"memory-{count}"), str(count)], text=True, timeout=30)
        print(output, end="", flush=True)
        peaks.append(int(re.search(r"peak_rss_bytes=(\d+)", output).group(1)))
    # The larger fixture adds 80 MiB of archive history. A 16 MiB RSS allowance
    # tolerates process/runtime variation but rejects whole-history retention.
    assert peaks[1] <= peaks[0] + 16 * 1024 * 1024, peaks
    assert peaks[1] < 48 * 1024 * 1024, peaks
    print("PASS: 6x archive history increases peak RSS by at most 16 MiB; larger process stays below 48 MiB", flush=True)
