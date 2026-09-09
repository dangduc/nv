#!/usr/bin/env python3
"""Build and run the native Backups pane with an in-memory coordinator."""

from pathlib import Path
import subprocess


ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "build" / "BackupPreferences"
OUTPUT.mkdir(parents=True, exist_ok=True)
subprocess.run(
    [
        "xcrun", "clang", "-fno-objc-arc", "-Wno-incomplete-implementation",
        "-mmacosx-version-min=10.13",
        "-I", "Sources/Application", "-I", "Sources/Storage", "-I", "Sources/Preferences",
        "Tests/BackupPreferences/preferences.m",
        "Sources/Preferences/NVBackupPreferencesViewController.m",
        "-framework", "Cocoa", "-o", str(OUTPUT / "preferences"),
    ],
    cwd=ROOT, check=True,
)
subprocess.run([str(OUTPUT / "preferences"), str(OUTPUT / "pane.png")], cwd=ROOT, check=True, timeout=30)
