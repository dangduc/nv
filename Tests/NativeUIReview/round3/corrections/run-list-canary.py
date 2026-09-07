#!/usr/bin/env python3
"""Require current native UI acceptance to reject the proven list appearance fault."""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import sys
import plistlib
import shutil
import signal
import subprocess
import tempfile
import uuid

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
sys.path.insert(0, str(REPO / "Tests"))
from compiler_support import include_flags

SOURCE = REPO / 'build/DerivedData/Build/Products/Development/nvALT.app'
FIXTURE = REPO / 'Tests/Regression/native-ui'



def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def stop_copy(binary):
    # Launch Services does not parent the app process. Match only this copy.
    listing = subprocess.run(['ps', '-axo', 'pid=,comm='], capture_output=True, text=True, check=True)
    for line in listing.stdout.splitlines():
        parts = line.strip().split(None, 1)
        if len(parts) == 2 and parts[1] == str(binary):
            try:
                os.kill(int(parts[0]), signal.SIGTERM)
            except ProcessLookupError:
                pass


def run_case(name, fault=None):
    with tempfile.TemporaryDirectory(prefix='nvalt-list-correction-') as directory:
        root = Path(directory)
        app = root / 'List Correction.app'
        shutil.copytree(SOURCE, app, symlinks=True)
        info_path = app / 'Contents/Info.plist'
        info = plistlib.loads(info_path.read_bytes())
        domain = 'org.nvalt.window-tests.' + uuid.uuid4().hex
        info['CFBundleIdentifier'] = domain
        info_path.write_bytes(plistlib.dumps(info))
        for folder in ('Notes', 'Support', 'Temp'):
            (root / folder).mkdir()
        # Byte-for-byte fixture copies; included metadata checks stay unchanged.
        for filename in ('probes.m', 'checks.inc'):
            shutil.copyfile(FIXTURE / filename, root / filename)
            assert digest(FIXTURE / filename) == digest(root / filename)
        dylib = root / 'Canary.dylib'
        compile_result = subprocess.run([
            'xcrun', 'clang', '-arch', 'x86_64', '-mmacosx-version-min=10.13', '-dynamiclib',
            '-undefined', 'dynamic_lookup', '-fno-objc-arc', '-Wno-deprecated-declarations',
            *include_flags(REPO), '-include', str(REPO / 'Config/Notation_Prefix.pch'),
            '-framework', 'Cocoa', '-framework', 'Carbon', '-o', str(dylib),
            str(root / 'probes.m'), str(HERE.parent / 'test_contrarian/mutations.m')], capture_output=True, text=True)
        (HERE / (name + '-compile.txt')).write_text(compile_result.stdout + compile_result.stderr)
        compile_result.check_returncode()
        environment = dict(os.environ)
        for key in list(environment):
            if key.startswith('NV_') or key == 'DYLD_INSERT_LIBRARIES':
                environment.pop(key)
        injected = dict(NV_WINDOW_TEST_DIRECTORY=str(root), DYLD_INSERT_LIBRARIES=str(dylib),
                        TMPDIR=str(root / 'Temp') + '/')
        if fault:
            injected['NV_R3_REMOVE_LIST_AQUA'] = '1'
        artifacts = HERE / (name + '-pixels')
        artifacts.mkdir(exist_ok=True)
        injected['NV_UI_ARTIFACTS'] = str(artifacts)
        binary = app / 'Contents/MacOS' / info['CFBundleExecutable']
        output_path = root / 'run.log'
        command = ['open', '-W', '-n', '--stdout', str(output_path), '--stderr', str(output_path)]
        for key, value in injected.items():
            command.extend(['--env', key + '=' + value])
        command.extend([str(app), '--args', '-ShowDockIcon', 'YES', '-StatusBarItem', 'NO',
                        '-QuitWhenClosingMainWindow', 'NO', '-SUEnableAutomaticChecks', 'NO'])
        try:
            result = subprocess.run(command, env=environment, timeout=90, capture_output=True, text=True)
            output = output_path.read_text() if output_path.exists() else ''
            output += result.stdout + result.stderr
        finally:
            stop_copy(binary)
            subprocess.run(['defaults', 'delete', domain], capture_output=True)
        (HERE / (name + '.txt')).write_text(output)
        failures = [line.split('FAIL: ', 1)[1] for line in output.splitlines() if 'FAIL: ' in line]
        passed = 'NATIVE UI TESTS PASSED' in output and not failures
        summary = dict(name=name, launcher_exit=result.returncode, fixture_passed=passed,
                       passed_assertions=output.count('PASS: '),
                       activated_fault_calls=output.count('MUTATION ACTIVATED:'), failures=failures)
        print(json.dumps(summary), flush=True)
        if fault:
            assert not passed and summary['activated_fault_calls'] > 0, summary
            assert failures == ['unselected alternating note rows retain a pale rendered background under the window appearance'], summary
        else:
            assert result.returncode == 0 and passed and not summary['activated_fault_calls'], summary
        return summary


def main():
    head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=REPO, text=True).strip()
    lock_path = REPO / 'build/pr-review/gui.lock'
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    with lock_path.open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        info = plistlib.loads((SOURCE / 'Contents/Info.plist').read_bytes())
        paths = [FIXTURE / 'probes.m', FIXTURE / 'checks.inc',
                 REPO / 'Tests/Regression/native-list/pixels.inc',
                 REPO / 'Tests/Regression/native-metadata/checks.inc',
                 SOURCE / 'Contents/MacOS' / info['CFBundleExecutable']]
        hashes = {str(path.relative_to(REPO)): digest(path) for path in paths}
        provenance = dict(source_head=head, sha256=hashes,
                          macos=subprocess.check_output(['sw_vers'], text=True),
                          xcode=subprocess.check_output(['xcodebuild', '-version'], text=True))
        (HERE / 'provenance.json').write_text(json.dumps(provenance, indent=2) + '\n')
        results = [run_case('list-baseline'), run_case('list-appearance-fault', fault=True)]
        assert hashes == {str(path.relative_to(REPO)): digest(path) for path in paths}
        (HERE / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
        print('LIST CANARY PASSED: current acceptance passes and rejects the activated appearance-removal fault.', flush=True)


if __name__ == '__main__':
    main()
