#!/usr/bin/env python3
"""Bounded native review probes. No shipping app or personal notes are opened."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
includes = [flag for folder in sorted({p.parent for p in (ROOT / "Sources").rglob("*.h")}) for flag in ("-I", str(folder))]
with tempfile.TemporaryDirectory(prefix="nvalt-r1-luu-", dir=ROOT / "build") as temporary:
    temp = Path(temporary).resolve()
    common = ["xcrun", "clang", "-arch", "arm64", "-fno-objc-arc", "-fblocks", "-O1", "-Wno-deprecated-declarations", "-Wno-incomplete-implementation", "-mmacosx-version-min=11.0", "-DNVBACKUPSTORE_TESTING", *includes, "-I", str(ROOT)]
    # Reuse ONLY fixture classes and queue helpers. The controller and store
    # compile from their untouched production files, not extracted methods.
    fixture = (ROOT / "Tests/BackupCoordinator/coordinator.m").read_text()
    prefix = fixture.split("@implementation NVBackupStore")[0]
    prefix = prefix.replace('@"generation":@(generation), @"libraryIdentifier":', '@"encrypted":@NO, @"generation":@(generation), @"libraryIdentifier":')
    helpers = fixture[fixture.index("@implementation NVBackupArchive"):fixture.index("int main(")]
    (temp / "coordinator.m").write_text(prefix + helpers + (HERE / "coordinator-main.inc").read_text())
    subprocess.run([*common, str(temp / "coordinator.m"), str(ROOT / "Sources/Storage/NVBackupController.m"), str(ROOT / "Sources/Storage/NVBackupStore.m"), "-framework", "Cocoa", "-framework", "CoreServices", "-o", str(temp / "coordinator")], check=True)
    subprocess.run([str(temp / "coordinator"), str(temp / "coordinator-data")], check=True, timeout=30)
    subprocess.run([*common, str(HERE / "store-cost.m"), "-framework", "Foundation", "-o", str(temp / "store-cost")], check=True)
    subprocess.run([str(temp / "store-cost"), str(temp / "store-data")], check=True, timeout=30)
