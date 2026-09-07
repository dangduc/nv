#!/usr/bin/env python3
"""Challenge maintained history and selection tests with behavior removal.

Production sources and the shared app remain unchanged. Each case runs the
existing regression harness in its own copied app and temporary notes library.
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
REPO = HERE.parents[3]
SOURCE = REPO / 'build/DerivedData/Build/Products/Development/nvALT.app'
LOCK_PATH = REPO / 'build/pr-review/gui.lock'
LOCK_PATH.parent.mkdir(parents=True, exist_ok=True)


def run_case(suite, mutation=None):
    with tempfile.TemporaryDirectory(prefix='nvalt-acceptance-canary-') as directory:
        root = Path(directory)
        app = root / 'Acceptance Canary.app'
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
        dylib = root / 'Canary.dylib'
        subprocess.run(['xcrun', 'clang', '-arch', 'x86_64', '-mmacosx-version-min=10.13', '-dynamiclib',
            '-undefined', 'dynamic_lookup', '-fno-objc-arc', '-Wno-deprecated-declarations',
            '-I', str(REPO), '-I', str(REPO / 'RBSplitView'), '-I', str(REPO / 'PTHotKeys'),
            '-I', str(REPO / 'ODBEditor'), '-include', str(REPO / 'Notation_Prefix.pch'),
            '-framework', 'Cocoa', '-framework', 'Carbon', '-o', str(dylib),
            str(REPO / 'Tests/Regression' / suite / 'probes.m'),
            str(HERE / 'history_selection_mutations.m')], check=True, capture_output=True, text=True)
        environment = dict(os.environ, NV_WINDOW_TEST_DIRECTORY=str(root), DYLD_INSERT_LIBRARIES=str(dylib), TMPDIR=str(root / 'Temp') + '/')
        environment.pop('NV_WINDOW_TEST_RELAUNCH', None)
        environment.pop('NV_ACCEPTANCE_MUTATION', None)
        if mutation:
            environment['NV_ACCEPTANCE_MUTATION'] = mutation
        args = [str(app / 'Contents/MacOS' / info['CFBundleExecutable']), '-ShowDockIcon', 'YES',
            '-StatusBarItem', 'NO', '-QuitWhenClosingMainWindow', 'NO', '-SUEnableAutomaticChecks', 'NO']
        try:
            result = subprocess.run(args, env=environment, timeout=30, capture_output=True, text=True)
        finally:
            subprocess.run(['defaults', 'delete', info['CFBundleIdentifier']], capture_output=True)
        output = result.stdout + result.stderr
        count = output.count('PASS: ')
        injected = output.count('MUTATION: ')
        print(f'{suite} {mutation or "baseline"}: exit={result.returncode} assertions={count} mutations={injected}', flush=True)
        for line in output.splitlines():
            if 'FAIL:' in line or 'TESTS PASSED' in line:
                print(line, flush=True)
        return result.returncode, count, injected, output


with LOCK_PATH.open('w') as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    editing = run_case('editing')
    assert editing[0] == 0 and 'EDITING HISTORY REGRESSION TESTS PASSED' in editing[3], editing[3]
    history = run_case('editing', 'history')
    assert history[0] == 1 and history[2] > 0 and any(message in history[3] for message in (
        'FAIL: undo finishes composition in every attached editor',
        'FAIL: undo preserves the deferred external update and removes only the local composition')), history[3]
    selection = run_case('selections')
    assert selection[0] == 0 and 'SELECTION REGRESSION TESTS PASSED' in selection[3], selection[3]
    whole_snapshot = run_case('selections', 'selection')
    assert whole_snapshot[0] == 1 and whole_snapshot[2] > 0 and \
        'FAIL: undo preserves peer selection before the edited suffix' in whole_snapshot[3], whole_snapshot[3]
    print('ACCEPTANCE CANARIES PASSED: history and selection suites reject their respective behavior-removal mutations.')
