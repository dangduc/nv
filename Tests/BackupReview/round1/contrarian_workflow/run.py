#!/usr/bin/env python3
"""Native Backups pane action ordering probe, using an in-memory coordinator."""
from pathlib import Path
import subprocess
import sys
ROOT = Path(__file__).resolve().parents[4]
OUTPUT = ROOT / 'build/BackupReview/round1/contrarian_workflow'
OUTPUT.mkdir(parents=True, exist_ok=True)
subprocess.run(['xcrun', 'clang', '-fno-objc-arc', '-Wno-incomplete-implementation',
    '-mmacosx-version-min=10.13', '-I', 'Sources/Application', '-I', 'Sources/Storage',
    '-I', 'Sources/Preferences', str(Path(__file__).with_name('probe.m')),
    'Sources/Preferences/NVBackupPreferencesViewController.m', '-framework', 'Cocoa',
    '-o', str(OUTPUT / 'probe')], cwd=ROOT, check=True)
subprocess.run([str(OUTPUT / 'probe'), *sys.argv[1:]], cwd=ROOT, check=True, timeout=30)
