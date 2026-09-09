#!/usr/bin/env python3
"""Native pane action ordering checks with an in-memory coordinator."""
from pathlib import Path
import argparse
import subprocess

ROOT = Path(__file__).resolve().parents[4]
OUTPUT = ROOT / 'build/BackupReview/round1/contrarian_workflow'
OUTPUT.mkdir(parents=True, exist_ok=True)
parser = argparse.ArgumentParser()
parser.add_argument('--negative-mutations', action='store_true')
parser.add_argument('--expect-regression', action='store_true')
parser.add_argument('--expect-fixed', action='store_true', help='Compatibility option; fixed behavior is the default.')
args = parser.parse_args()
production = ROOT / 'Sources/Preferences/NVBackupPreferencesViewController.m'


def build(source, name):
    binary = OUTPUT / name
    subprocess.run(['xcrun', 'clang', '-fno-objc-arc', '-Wno-incomplete-implementation',
        '-mmacosx-version-min=10.13', '-I', 'Sources/Application', '-I', 'Sources/Storage',
        '-I', 'Sources/Preferences', str(Path(__file__).with_name('probe.m')), str(source),
        '-framework', 'Cocoa', '-o', str(binary)], cwd=ROOT, check=True)
    return binary


binary = build(production, 'probe')
subprocess.run([str(binary), *(['--expect-regression'] if args.expect_regression else [])],
               cwd=ROOT, check=True, timeout=30)
if args.negative_mutations:
    source = production.read_text()
    mutations = {
        'discard-active-editor': ('[field setEnabled:[controller hasLibrary]];', '[field setEnabled:configurable];'),
        'skip-manual-commit': ('if ([self prepareForAction]) [[self backupController] backupNow:sender];',
                               '[[self backupController] backupNow:sender];'),
    }
    for name, (before, after) in mutations.items():
        assert source.count(before) == 1, (name, 'mutation target moved')
        path = OUTPUT / f'{name}.m'
        path.write_text(source.replace(before, after, 1))
        mutated_binary = build(path, name)
        result = subprocess.run([str(mutated_binary)], cwd=ROOT, timeout=30, capture_output=True, text=True)
        assert result.returncode != 0, (name, 'negative mutation unexpectedly passed')
        failure = next((line for line in result.stderr.splitlines() if 'FAIL:' in line), result.stderr.strip())
        print(f'REJECTED: {name}: {failure}', flush=True)
