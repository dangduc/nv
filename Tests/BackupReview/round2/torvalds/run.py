#!/usr/bin/env python3
"""Native maintenance and deletion checks with disposable backup fixtures."""
from pathlib import Path
import argparse
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
parser = argparse.ArgumentParser()
parser.add_argument("--deletion-mutation", action="store_true", help="Remove the owner comparison in a temporary source copy; the regression must fail.")
args = parser.parse_args()
with tempfile.TemporaryDirectory(prefix="nv-review-torvalds-r2-") as temporary:
    temporary = Path(temporary).resolve()
    executable = temporary / "probe"
    production = ROOT / "Sources/Storage/NVBackupStore.m"
    if args.deletion_mutation:
        source = production.read_text()
        before = 'BOOL matchingOwner = owner && [[owner objectForKey:@"libraryIdentifier"] isEqual:identifier];'
        assert source.count(before) == 1
        source = source.replace(before, 'BOOL matchingOwner = owner != nil;', 1)
        before = 'matchingOwner ? NVSnapshots(root, directory, identifier, error) : nil;'
        assert source.count(before) == 1
        source = source.replace(before, 'matchingOwner ? NVSnapshots(root, directory, [owner objectForKey:@"libraryIdentifier"], error) : nil;', 1)
        production = temporary / "deletion-mutation.m"
        production.write_text(source)
    subprocess.run([
        "xcrun", "clang", "-fblocks", "-fno-objc-arc", "-Wall", "-Wextra", "-Werror",
        "-mmacosx-version-min=10.13", "-DNVBACKUPSTORE_TESTING", "-framework", "Foundation",
        "-I", str(ROOT / "Sources/Storage"), str(production),
        str(HERE / "main.m"), "-o", str(executable),
    ], check=True, timeout=60)
    subprocess.run([str(executable), str(temporary / "fixtures")], check=True, timeout=60)
