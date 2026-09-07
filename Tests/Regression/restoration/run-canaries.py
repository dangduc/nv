#!/usr/bin/env python3
"""Verify that the required suite detects removed query and field restoration.

Uses test-only runtime swizzling in copied apps, never production source or app.
All generated data is temporary. Run outside the sandbox for Rosetta/Cocoa.
"""
import fcntl
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import uuid

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
SOURCE = REPO / 'build/DerivedData/Build/Products/Development/nvALT.app'
LOCK_PATH = REPO / 'build/pr-review/gui.lock'
LOCK_PATH.parent.mkdir(parents=True, exist_ok=True)


def run_case(name, mutation=None):
    with tempfile.TemporaryDirectory(prefix='nvalt-query-canary-') as directory:
        root = Path(directory)
        app = root / 'Query Canary.app'
        shutil.copytree(SOURCE, app, symlinks=True)
        info_path = app / 'Contents/Info.plist'
        info = plistlib.loads(info_path.read_bytes())
        original_id = info['CFBundleIdentifier']
        info['CFBundleIdentifier'] = 'org.nvalt.window-tests.' + uuid.uuid4().hex
        assert info['CFBundleIdentifier'] != original_id
        assert app.resolve().is_relative_to(root.resolve())
        info_path.write_bytes(plistlib.dumps(info))
        for folder in ('Notes', 'Support', 'Temp'):
            (root / folder).mkdir()
        harness = (REPO / 'Tests/MultipleWindowsTests.m').read_text()
        harness_path = root / 'IntegrationCanary.m'
        harness_path.write_text(harness)
        dylib = root / 'Canary.dylib'
        subprocess.run(['xcrun', 'clang', '-arch', 'x86_64', '-mmacosx-version-min=10.13', '-dynamiclib',
            '-undefined', 'dynamic_lookup', '-fno-objc-arc', '-Wno-deprecated-declarations',
            '-I', str(REPO), '-I', str(REPO / 'RBSplitView'), '-I', str(REPO / 'PTHotKeys'),
            '-I', str(REPO / 'ODBEditor'), '-include', str(REPO / 'Notation_Prefix.pch'),
            '-framework', 'Cocoa', '-framework', 'Carbon', '-o', str(dylib), str(harness_path),
            str(HERE / 'query_mutation.m')], check=True, capture_output=True, text=True)
        environment = dict(os.environ, NV_WINDOW_TEST_DIRECTORY=str(root), DYLD_INSERT_LIBRARIES=str(dylib), TMPDIR=str(root / 'Temp') + '/')
        environment.pop('NV_WINDOW_TEST_RELAUNCH', None)
        environment.pop('NV_RESTORE_MUTATION', None)
        if mutation:
            environment['NV_RESTORE_MUTATION'] = mutation
        args = [str(app / 'Contents/MacOS' / info['CFBundleExecutable']), '-ShowDockIcon', 'YES',
            '-StatusBarItem', 'NO', '-QuitWhenClosingMainWindow', 'NO', '-SUEnableAutomaticChecks', 'NO']
        outputs = []
        exit_code = 0
        try:
            for launch in range(2):
                if launch:
                    environment['NV_WINDOW_TEST_RELAUNCH'] = '1'
                result = subprocess.run(args, env=environment, timeout=30, capture_output=True, text=True)
                outputs.append(result.stdout + result.stderr)
                exit_code = result.returncode
                if exit_code:
                    break
        finally:
            subprocess.run(['defaults', 'delete', info['CFBundleIdentifier']], capture_output=True)
        output = '\n'.join(outputs)
        count = output.count('PASS: ')
        injected = output.count('MUTATION: ')
        print(f'{name}: exit={exit_code} assertions={count} mutations={injected}', flush=True)
        for line in output.splitlines():
            if 'FAIL:' in line or 'TESTS PASSED' in line:
                print(line, flush=True)
        return exit_code, count, injected, output


with LOCK_PATH.open('w') as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    baseline = run_case('current suite baseline')
    assert baseline[0] == 0 and 'RELAUNCH TESTS PASSED' in baseline[3], baseline[3]
    query = run_case('query restoration removed', mutation='search')
    assert query[0] != 0 and query[2] > 0 and \
        'FAIL: relaunch restores distinct non-empty browser queries' in query[3], query[3]
    field = run_case('search field restoration removed', mutation='field')
    assert field[0] != 0 and field[2] > 0 and \
        'FAIL: relaunch restores each browser search field' in field[3], field[3]
    print('RESTORATION CANARIES PASSED: query and visible-field behavior removal both fail the required suite.')
