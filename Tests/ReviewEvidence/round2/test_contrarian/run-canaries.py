#!/usr/bin/env python3
"""Measure whether the current acceptance suite detects archived note-body loss.

Uses test-only runtime swizzling in copied apps, never production source or app.
All generated data is temporary. Run outside the sandbox for Rosetta/Cocoa.
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


def run_case(name, mutation=None, stronger=False):
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
        if stronger:
            needle = '        [[reopened window] makeKeyAndOrderFront:self]; [reopened searchForString:@"beta"]; Pump();'
            assert harness.count(needle) == 1
            harness = harness.replace(needle, needle + '\n' + """        LinkingEditor *durableEditor = [reopened valueForKey:@"textView"];
        [[reopened window] makeFirstResponder:durableEditor];
        [durableEditor insertText:@" persisted edit" replacementRange:NSMakeRange([[durableEditor string] length], 0)]; Pump();""")
            needle = '            Check([[app browserControllers][0] selectedNoteObject] != nil,'
            assert harness.count(needle) == 1
            harness = harness.replace(needle, """            Check([[[((NoteObject *)[[library allNotes] lastObject]) contentString] string] isEqualToString:@"beta only persisted edit"],
                @"relaunch preserves the exact body edited in a browser");
""" + needle)
        harness_path = root / 'IntegrationCanary.m'
        harness_path.write_text(harness)
        dylib = root / 'Canary.dylib'
        subprocess.run(['xcrun', 'clang', '-arch', 'x86_64', '-mmacosx-version-min=10.13', '-dynamiclib',
            '-undefined', 'dynamic_lookup', '-fno-objc-arc', '-Wno-deprecated-declarations',
            *include_flags(REPO), '-include', str(REPO / 'Config/Notation_Prefix.pch'),
            '-framework', 'Cocoa', '-framework', 'Carbon', '-o', str(dylib), str(harness_path),
            str(HERE / 'body_mutation.m')], check=True, capture_output=True, text=True)
        environment = dict(os.environ, NV_WINDOW_TEST_DIRECTORY=str(root), DYLD_INSERT_LIBRARIES=str(dylib), TMPDIR=str(root / 'Temp') + '/')
        environment.pop('NV_WINDOW_TEST_RELAUNCH', None)
        environment.pop('NV_BODY_MUTATION', None)
        if mutation:
            environment['NV_BODY_MUTATION'] = mutation
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
    assert baseline[0] == 0 and baseline[1] == 47, baseline[3]
    empty = run_case('empty body control', mutation='empty')
    assert empty[0] != 0 and empty[2] > 0 and \
        'FAIL: shared library flushes successfully' in empty[3], empty[3]
    survived = run_case('current suite with same-length body substitution', mutation='replace')
    assert survived[0] == 0 and survived[1] == 47 and survived[2] > 0, survived[3]
    stronger = run_case('browser-edit durability fixture baseline', stronger=True)
    assert stronger[0] == 0 and stronger[1] == 48, stronger[3]
    killed = run_case('durability fixture with same-length body substitution', mutation='replace', stronger=True)
    assert killed[0] != 0 and killed[2] > 0 and \
        'FAIL: relaunch preserves the exact body edited in a browser' in killed[3], killed[3]
    print('BODY CANARY CONFIRMED: current checks reject length loss but miss same-length body substitution; the edited-body relaunch assertion detects it.')
