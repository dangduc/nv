#!/usr/bin/env python3
"""Challenge appearance coverage through isolated runtime mutations.

Run outside the sandbox for Cocoa/Rosetta. No production files change.
"""
import fcntl
import os
from pathlib import Path
import sys
import plistlib
import shutil
import subprocess
import tempfile
import uuid

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
sys.path.insert(0, str(REPO / "Tests"))
from compiler_support import include_flags

SOURCE = REPO / 'build/DerivedData/Build/Products/Development/nvALT.app'
LOCK_PATH = REPO / 'build/pr-review/gui.lock'
LOCK_PATH.parent.mkdir(parents=True, exist_ok=True)


def run_case(name, mutation=False, automatic=False):
    with tempfile.TemporaryDirectory(prefix='nvalt-appearance-canary-') as directory:
        root = Path(directory)
        app = root / 'Appearance Canary.app'
        shutil.copytree(SOURCE, app, symlinks=True)
        info_path = app / 'Contents/Info.plist'
        info = plistlib.loads(info_path.read_bytes())
        info['CFBundleIdentifier'] = 'org.nvalt.window-tests.' + uuid.uuid4().hex
        info_path.write_bytes(plistlib.dumps(info))
        for folder in ('Notes', 'Support', 'Temp'):
            (root / folder).mkdir()
        fixture = REPO / 'Tests/Regression/native-ui'
        (root / 'probes.m').write_text((fixture / 'probes.m').read_text())
        checks = (fixture / 'checks.inc').read_text()
        direct_update = '                [self browserAppearanceChanged];\n'
        assert checks.count(direct_update) == 1
        if automatic:
            checks = checks.replace(direct_update, '')
        (root / 'checks.inc').write_text(checks)
        dylib = root / 'Canary.dylib'
        subprocess.run(['xcrun', 'clang', '-arch', 'x86_64', '-mmacosx-version-min=10.13', '-dynamiclib',
            '-undefined', 'dynamic_lookup', '-fno-objc-arc', '-Wno-deprecated-declarations',
            *include_flags(REPO), '-include', str(REPO / 'Config/Notation_Prefix.pch'),
            '-framework', 'Cocoa', '-framework', 'Carbon', '-o', str(dylib), str(root / 'probes.m'),
            str(HERE / 'appearance_mutation.m')], check=True, capture_output=True, text=True)
        environment = dict(os.environ, NV_WINDOW_TEST_DIRECTORY=str(root), DYLD_INSERT_LIBRARIES=str(dylib),
                           TMPDIR=str(root / 'Temp') + '/')
        for key in ('NV_APPEARANCE_MUTATION', 'NV_UI_FULL_SCREEN', 'NV_UI_ARTIFACTS'):
            environment.pop(key, None)
        if mutation:
            environment['NV_APPEARANCE_MUTATION'] = '1'
        args = [str(app / 'Contents/MacOS' / info['CFBundleExecutable']), '-ShowDockIcon', 'YES',
                '-StatusBarItem', 'NO', '-QuitWhenClosingMainWindow', 'NO', '-SUEnableAutomaticChecks', 'NO']
        try:
            result = subprocess.run(args, env=environment, timeout=90, capture_output=True, text=True)
        finally:
            subprocess.run(['defaults', 'delete', info['CFBundleIdentifier']], capture_output=True)
        output = result.stdout + result.stderr
        (HERE / (name + '.txt')).write_text(output)
        print(f'{name}: exit={result.returncode} assertions={output.count("PASS: ")} mutations={output.count("MUTATION: ")}', flush=True)
        for line in output.splitlines():
            if 'FAIL:' in line or 'TESTS PASSED' in line:
                print(line, flush=True)
        return result.returncode, output


with LOCK_PATH.open('w') as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    baseline = run_case('original-baseline')
    assert baseline[0] == 0, baseline[1]
    survived = run_case('original-mutation', mutation=True)
    assert survived[0] == 0 and 'MUTATION:' in survived[1], survived[1]
    automatic = run_case('automatic-baseline', automatic=True)
    assert automatic[0] == 0, automatic[1]
    killed = run_case('automatic-mutation', mutation=True, automatic=True)
    assert killed[0] != 0 and 'FAIL: system editor background follows the window appearance' in killed[1], killed[1]
    print('CANARY CONFIRMED: original checks miss callback removal; automatic checks detect it.')
