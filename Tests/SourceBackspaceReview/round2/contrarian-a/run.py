#!/usr/bin/env python3
"""Review maintained runner decisions with controlled child outputs, without GUI."""
from contextlib import redirect_stdout, redirect_stderr
import ast
import hashlib
import io
import json
import os
from pathlib import Path
import plistlib
import runpy
import subprocess
import sys
import tempfile
from types import SimpleNamespace
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
FILES = ['Sources/Browser/AppController.m', 'Sources/Browser/AppController_Search.m',
         'Sources/Editor/LinkingEditor.h', 'Sources/Editor/LinkingEditor.m',
         'Tests/SourceBackspace/run.py', 'Tests/SourceBackspace/probe-body.m',
         'Tests/SourceBackspace/support.h', 'Tests/MultipleWindowsTests.m',
         'Tests/FuzzySearch/HighlightBounds/run.py', 'Tests/FuzzySearch/HighlightBounds/probe.m',
         'Tests/FuzzySearch/Highlights/run.py', 'Tests/FuzzySearch/Highlights/probe.m',
         'Tests/run-regression-tests.py']
def hashes():
    return {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in FILES}

before = hashes()
head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
records = []
checks = 0
def check(value, message):
    global checks
    if not value:
        raise AssertionError(message)
    checks += 1
    records.append('PASS: ' + message)

def source_runner(root, label, log, code, *, negative=False, inherited_repro=False, timeout=False):
    app = root / (label + '.app')
    (app / 'Contents/MacOS').mkdir(parents=True)
    (app / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable': 'stub', 'CFBundleIdentifier': 'review.stub'}))
    (app / 'Contents/MacOS/stub').write_bytes(b'review stub, never executable')
    output = root / (label + '-output')
    calls = {}
    class Child:
        pid = 987654
        def __init__(self, command, **kw):
            calls['env'] = kw['env']
            calls['command'] = command
            calls['copied_app'] = Path(command[0]).parents[2]
            calls['isolated_id'] = plistlib.loads((calls['copied_app'] / 'Contents/Info.plist').read_bytes())['CFBundleIdentifier']
            calls['stdout'] = kw['stdout']
        def wait(self, timeout):
            calls['timeout'] = timeout
            calls['stdout'].write(log)
            calls['stdout'].flush()
            if calls.get('raise_timeout'):
                raise subprocess.TimeoutExpired('stub', timeout)
            return code
        def kill(self):
            calls['killed'] = True
    calls['raise_timeout'] = timeout
    argv = [str(ROOT / FILES[4]), '--app', str(app), '--output', str(output)]
    if negative:
        argv.append('--expect-original-crash')
    environment = dict(os.environ)
    environment.pop('NV_BACKSPACE_REPRO_ONLY', None)
    if inherited_repro:
        environment['NV_BACKSPACE_REPRO_ONLY'] = '1'
    stream = io.StringIO()
    # All application and compiler subprocesses are controlled. This runs the
    # maintained Python runner's copying, isolation, and result decisions.
    with patch.object(sys, 'argv', argv), patch.dict(os.environ, environment, clear=True), \
         patch('subprocess.run', return_value=subprocess.CompletedProcess([], 0)), \
         patch('subprocess.check_output', return_value=str(root / 'fake-common.git') + '\n'), \
         patch('subprocess.Popen', Child), redirect_stdout(stream), redirect_stderr(stream):
        try:
            runpy.run_path(str(ROOT / FILES[4]), run_name='__main__')
        except SystemExit as exc:
            exit_value = exc.code
        else:
            raise AssertionError('Maintained runner did not exit')
    report = json.loads((output / 'results.json').read_text()) if (output / 'results.json').exists() else None
    records.append(json.dumps({'scenario': label, 'exit': exit_value, 'report': report,
                               'inherited_repro_in_child': calls['env'].get('NV_BACKSPACE_REPRO_ONLY'),
                               'kill_sent': calls.get('killed', False)}))
    return exit_value, report, calls

def bounds_runner(root, name, code, stderr, *, positive=False):
    source = (ROOT / FILES[8]).read_text()
    tree = ast.parse(source)
    function = next(node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name == 'run_case')
    function_module = ast.Module(body=[function], type_ignores=[])
    output = root / name
    output.mkdir()
    calls = []
    def child(command, **kw):
        calls.append(command)
        # First call compiles. Second call supplies controlled probe output.
        return subprocess.CompletedProcess(command, 0 if len(calls) == 1 else code, '', '' if len(calls) == 1 else stderr)
    namespace = {'OUT': output, 'HERE': ROOT / 'Tests/FuzzySearch/HighlightBounds',
                 'flags': [], 'objects': [], 'a': SimpleNamespace(build_only=False),
                 'os': os, 'subprocess': SimpleNamespace(run=child)}
    exec(compile(function_module, str(ROOT / FILES[8]), 'exec'), namespace)
    stream = io.StringIO()
    try:
        with redirect_stdout(stream), redirect_stderr(stream):
            namespace['run_case'](name, 'refresh', 'editor', 'query', positive)
    except SystemExit as exc:
        accepted, exit_value = False, exc.code
    else:
        accepted, exit_value = True, None
    records.append(json.dumps({'bounds_scenario': name, 'treated_as_expected_result': accepted,
                               'exit': exit_value, 'output': stream.getvalue()}))
    return accepted

with tempfile.TemporaryDirectory(prefix='backspace-review-runner-') as temporary:
    root = Path(temporary)
    full_log = 'PASS: fixture\n' * 310 + 'SOURCE BACKSPACE PASSED (310 checks)\n'
    partial_log = 'PASS: first fixture\n' * 12 + 'SOURCE BACKSPACE PASSED (original failure did not recur)\n'
    correct_crash = 'BACKSPACE FIRST DELETE length=26\nSOURCE BACKSPACE EXCEPTION NSRangeException Index 25 out of bounds; string length 25\n'
    result, report, calls = source_runner(root, 'full', full_log, 0)
    check(result == 0 and report['passed'] and report['checks'] == 310, 'full completion marker accepts the controlled 310-check success')
    check(calls['isolated_id'].startswith('org.nvalt.window-tests.') and str(calls['copied_app']) != str(root / 'full.app'), 'runner changes the copied application identifier before launch')
    check(Path(calls['env']['NV_WINDOW_TEST_DIRECTORY']) == calls['copied_app'].parent, 'child library root belongs to the disposable copied app')
    check(calls['timeout'] == 150, 'native process wait has the documented timeout')
    result, report, calls = source_runner(root, 'ambient-repro', partial_log, 0, inherited_repro=True)
    check(calls['env'].get('NV_BACKSPACE_REPRO_ONLY') == '1', 'normal runner inherits the first-case-only environment switch')
    check(result == 0 and report['passed'] and report['checks'] == 12, 'FINDING: normal runner accepts first-case-only success as full regression success')
    body = (ROOT / FILES[5]).read_text()
    check('if (getenv("NV_BACKSPACE_REPRO_ONLY"))' in body and 'SOURCE BACKSPACE PASSED (original failure did not recur)' in body, 'native fixture contains the inherited switch and accepted early success marker')
    result, report, _ = source_runner(root, 'original-match', correct_crash, 1, negative=True)
    check(result == 0 and report['original_range_exception'], 'negative control accepts the controlled original range signature')
    for name, log, code in [
        ('wrong-index', correct_crash.replace('Index 25', 'Index 24'), 1),
        ('unrelated-exception', correct_crash.replace('NSRangeException', 'NSInvalidArgumentException'), 1),
        ('signal-without-signature', 'BACKSPACE FIRST DELETE length=26\n', -11),
        ('successful-old-app', partial_log, 0),
    ]:
        result, report, _ = source_runner(root, name, log, code, negative=True)
        check(result == 1 and not report['passed'], 'negative control rejects ' + name)
    result, report, calls = source_runner(root, 'timeout', '', -9, negative=True, timeout=True)
    check(result != 0 and report is None and calls.get('killed'), 'negative control rejects timeout and sends kill to its disposable child')
    check(bounds_runner(root, 'expected-assertion', 1, 'FAIL: repeated invalidations coalesce one delayed selector\n'), 'HighlightBounds accepts a controlled intended mutation assertion')
    check(bounds_runner(root, 'loader-failure', 127, 'dyld: Library not loaded: /missing/review.dylib\n'), 'FINDING: HighlightBounds also accepts an unrelated loader failure as a mutation rejection')
    check(bounds_runner(root, 'unrelated-signal', -11, ''), 'FINDING: HighlightBounds also accepts an unrelated signal as a mutation rejection')
    check(not bounds_runner(root, 'surviving-mutant', 0, ''), 'HighlightBounds rejects a mutant that exits successfully')
    check(not bounds_runner(root, 'failed-positive', 127, 'dyld: Library not loaded\n', positive=True), 'HighlightBounds rejects the same loader failure for a positive run')

    # The aggregate is also real Python. Replace only its child execution.
    aggregate_calls = []
    def aggregate_child(command, **kw):
        aggregate_calls.append(command)
        raise subprocess.CalledProcessError(1, command)
    stream = io.StringIO()
    try:
        with patch('subprocess.run', aggregate_child), redirect_stdout(stream):
            runpy.run_path(str(ROOT / FILES[12]), run_name='__main__')
    except subprocess.CalledProcessError:
        failed = True
    else:
        failed = False
    check(failed and len(aggregate_calls) == 1 and aggregate_calls[0][1].endswith('/Tests/SourceBackspace/run.py'), 'aggregate runs SourceBackspace first and stops on its failure')
    check('ALL REGRESSION CHECKS PASSED' not in stream.getvalue(), 'aggregate does not print all-pass after a child failure')

after = hashes()
check(before == after, 'production and reviewed test source hashes remain unchanged')
manifest = {'base': '54ce3b8f94c382e8a4c20c871b8fb20dc30cc376', 'reviewed_head': head,
            'sha256_before': before, 'sha256_after': after, 'checks': checks,
            'scope': 'Maintained Python runner decisions with controlled compiler/application subprocess outputs. No native app, editor, or GUI operation.'}
(HERE / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
(HERE / 'output.txt').write_text('\n'.join(records) + '\n')
print('\n'.join(records))
print(f'Completed {checks} runner-evidence checks.')
