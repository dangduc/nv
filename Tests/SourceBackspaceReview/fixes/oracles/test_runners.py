"""Fail-closed runner decisions with controlled child processes; no app launch."""
import ast
from contextlib import redirect_stderr, redirect_stdout
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
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[4]
SOURCE_RUNNER = ROOT / 'Tests/SourceBackspace/run.py'
BOUNDS_RUNNER = ROOT / 'Tests/FuzzySearch/HighlightBounds/run.py'
FULL_LOG = 'PASS: fixture\n' * 310 + 'SOURCE BACKSPACE PASSED (310 checks)\n'
PARTIAL_LOG = 'PASS: first fixture\n' * 12 + 'SOURCE BACKSPACE PASSED (original failure did not recur)\n'
CRASH_LOG = ('BACKSPACE FIRST DELETE length=26\n'
             'SOURCE BACKSPACE EXCEPTION NSRangeException Index 25 out of bounds; string length 25\n')


class SourceRunnerTests(unittest.TestCase):
    def run_source(self, log=FULL_LOG, exit_code=0, *, negative=False, inherited=None, timeout=False):
        with tempfile.TemporaryDirectory(prefix='backspace-oracle-test-') as temporary:
            root = Path(temporary)
            app = root / 'Fixture.app'
            (app / 'Contents/MacOS').mkdir(parents=True)
            (app / 'Contents/Info.plist').write_bytes(plistlib.dumps({
                'CFBundleExecutable': 'fixture', 'CFBundleIdentifier': 'test.fixture'}))
            (app / 'Contents/MacOS/fixture').write_bytes(b'Not executable. All subprocesses are mocked.')
            output = root / 'results'
            calls = {}

            class Child:
                pid = 999999

                def __init__(self, command, **kwargs):
                    calls['command'] = command
                    calls['environment'] = kwargs['env']
                    calls['log'] = kwargs['stdout']

                def wait(self, timeout):
                    calls['log'].write(log)
                    calls['log'].flush()
                    if calls['timeout']:
                        raise subprocess.TimeoutExpired('mock fixture', timeout)
                    return exit_code

                def kill(self):
                    calls['killed'] = True

            calls['timeout'] = timeout
            argv = [str(SOURCE_RUNNER), '--app', str(app), '--output', str(output)]
            if negative:
                argv.append('--expect-original-crash')
            environment = dict(os.environ)
            environment.pop('NV_BACKSPACE_REPRO_ONLY', None)
            if inherited is not None:
                environment['NV_BACKSPACE_REPRO_ONLY'] = inherited
            stream = io.StringIO()
            with patch.object(sys, 'argv', argv), patch.dict(os.environ, environment, clear=True), \
                    patch('subprocess.run', return_value=subprocess.CompletedProcess([], 0)), \
                    patch('subprocess.check_output', return_value=str(root / 'fake.git') + '\n'), \
                    patch('subprocess.Popen', Child), redirect_stdout(stream), redirect_stderr(stream):
                with self.assertRaises(SystemExit) as raised:
                    runpy.run_path(str(SOURCE_RUNNER), run_name='__main__')
            report_path = output / 'results.json'
            report = json.loads(report_path.read_text()) if report_path.exists() else None
            return raised.exception.code, report, calls

    def test_full_suite_success(self):
        code, report, _ = self.run_source()
        self.assertEqual(code, 0)
        self.assertTrue(report['passed'])
        self.assertEqual(report['checks'], 310)
        self.assertEqual(report['mode'], 'production-regression')

    def test_normal_run_removes_every_inherited_repro_value(self):
        # getenv checks presence, so even an inherited empty string must disappear.
        for inherited in ('1', '0', ''):
            with self.subTest(inherited=inherited):
                code, report, calls = self.run_source(inherited=inherited)
                self.assertNotIn('NV_BACKSPACE_REPRO_ONLY', calls['environment'])
                self.assertEqual(code, 0)
                self.assertTrue(report['passed'])

    def test_partial_suite_marker_is_rejected(self):
        for inherited in (None, '1', ''):
            with self.subTest(inherited=inherited):
                code, report, calls = self.run_source(PARTIAL_LOG, inherited=inherited)
                self.assertNotIn('NV_BACKSPACE_REPRO_ONLY', calls['environment'])
                self.assertEqual(code, 1)
                self.assertFalse(report['passed'])

    def test_full_marker_without_successful_exit_is_rejected(self):
        for exit_code in (1, 127, -11):
            with self.subTest(exit_code=exit_code):
                code, report, _ = self.run_source(exit_code=exit_code)
                self.assertEqual(code, 1)
                self.assertFalse(report['passed'])

    def test_missing_or_incomplete_marker_is_rejected(self):
        for log in ('', 'PASS: fixture\n', 'SOURCE BACKSPACE PASSED\n',
                    'SOURCE BACKSPACE PASSED (0 checks)\n',
                    'SOURCE BACKSPACE PASSED (310 checks) unfinished\n'):
            with self.subTest(log=log):
                code, report, _ = self.run_source(log)
                self.assertEqual(code, 1)
                self.assertFalse(report['passed'])

    def test_timestamped_full_completion_is_accepted(self):
        log = '2026-09-09 21:10:00 nvALT[123:456] SOURCE BACKSPACE PASSED (310 checks)\n'
        code, report, _ = self.run_source(log)
        self.assertEqual(code, 0)
        self.assertTrue(report['passed'])

    def test_explicit_negative_mode_sets_its_own_switch(self):
        for inherited in (None, '0', ''):
            with self.subTest(inherited=inherited):
                code, report, calls = self.run_source(CRASH_LOG, 1, negative=True, inherited=inherited)
                self.assertEqual(calls['environment']['NV_BACKSPACE_REPRO_ONLY'], '1')
                self.assertEqual(code, 0)
                self.assertTrue(report['original_range_exception'])
                self.assertEqual(report['mode'], 'original-crash-negative-control')

    def test_negative_mode_rejects_success_or_wrong_failure(self):
        for log, exit_code in ((PARTIAL_LOG, 0), (FULL_LOG, 0),
                               (CRASH_LOG.replace('Index 25', 'Index 24'), 1),
                               ('dyld: Library not loaded\n', 127), ('', -11)):
            with self.subTest(log=log, exit_code=exit_code):
                code, report, _ = self.run_source(log, exit_code, negative=True)
                self.assertEqual(code, 1)
                self.assertFalse(report['passed'])

    def test_timeout_is_failure_without_success_report(self):
        code, report, calls = self.run_source(timeout=True)
        self.assertNotEqual(code, 0)
        self.assertIsNone(report)
        self.assertTrue(calls['killed'])


class HighlightBoundsRunnerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Compile the maintained function and its assertion map, skipping native builds.
        tree = ast.parse(BOUNDS_RUNNER.read_text())
        nodes = [node for node in tree.body if
                 (isinstance(node, ast.FunctionDef) and node.name == 'run_case') or
                 (isinstance(node, ast.Assign) and any(isinstance(target, ast.Name) and
                  target.id == 'EXPECTED_MUTATION_FAILURES' for target in node.targets))]
        cls.code = compile(ast.Module(body=nodes, type_ignores=[]), str(BOUNDS_RUNNER), 'exec')

    def run_bounds(self, name, exit_code, stderr='', stdout='', *, positive=False):
        with tempfile.TemporaryDirectory(prefix='bounds-oracle-test-') as temporary:
            calls = []

            def child(command, **kwargs):
                calls.append(command)
                if len(calls) == 1:
                    return subprocess.CompletedProcess(command, 0, '', '')
                return subprocess.CompletedProcess(command, exit_code, stdout, stderr)

            namespace = {'OUT': Path(temporary), 'HERE': BOUNDS_RUNNER.parent,
                         'flags': [], 'objects': [], 'a': SimpleNamespace(build_only=False),
                         'os': os, 'subprocess': SimpleNamespace(run=child)}
            exec(self.code, namespace)
            stream = io.StringIO()
            with redirect_stdout(stream), redirect_stderr(stream):
                try:
                    namespace['run_case'](name, 'refresh', 'editor', 'query', positive)
                except SystemExit as exc:
                    return False, str(exc.code), stream.getvalue(), calls
            return True, '', stream.getvalue(), calls

    def expected_failures(self):
        namespace = {}
        exec(self.code, namespace)
        return namespace['EXPECTED_MUTATION_FAILURES']

    def test_positive_success(self):
        accepted, _, output, _ = self.run_bounds('positive', 0, stdout='PASS: fixture\n', positive=True)
        self.assertTrue(accepted)
        self.assertIn('PASS: fixture', output)

    def test_positive_failure_is_not_accepted(self):
        for code in (1, 127, -11):
            with self.subTest(code=code):
                accepted, _, _, _ = self.run_bounds('positive', code, 'FAIL: fixture\n', positive=True)
                self.assertFalse(accepted)

    def test_every_named_mutation_accepts_its_exact_assertion(self):
        failures = self.expected_failures()
        self.assertEqual(len(failures), 11)
        for name, assertion in failures.items():
            with self.subTest(name=name):
                accepted, _, output, calls = self.run_bounds(name, 1, 'FAIL: ' + assertion + '\n')
                self.assertTrue(accepted)
                self.assertIn('REJECTED: ' + name, output)
                self.assertEqual(len(calls), 2)

    def test_every_named_mutation_rejects_unrelated_failure(self):
        for name in self.expected_failures():
            for code, stderr in ((127, 'dyld: Library not loaded\n'), (-11, ''),
                                 (1, 'FAIL: unrelated assertion\n'), (1, ''), (0, '')):
                with self.subTest(name=name, code=code, stderr=stderr):
                    accepted, error, output, _ = self.run_bounds(name, code, stderr)
                    self.assertFalse(accepted)
                    self.assertIn('expected assertion', error)
                    self.assertNotIn('REJECTED:', output)

    def test_expected_assertion_does_not_hide_wrong_exit(self):
        for name, assertion in self.expected_failures().items():
            for code in (0, 2, 127, -11):
                with self.subTest(name=name, code=code):
                    accepted, _, _, _ = self.run_bounds(name, code, 'FAIL: ' + assertion + '\n')
                    self.assertFalse(accepted)

    def test_assertion_must_be_exact_stderr_line(self):
        name = 'uncoalesced_invalidation'
        assertion = 'FAIL: ' + self.expected_failures()[name]
        for stderr, stdout in ((assertion + ' (different failure)\n', ''),
                               ('prefix ' + assertion + '\n', ''), ('', assertion + '\n')):
            with self.subTest(stderr=stderr, stdout=stdout):
                accepted, _, _, _ = self.run_bounds(name, 1, stderr, stdout)
                self.assertFalse(accepted)

    def test_unknown_mutation_has_no_implicit_success_path(self):
        accepted, error, output, calls = self.run_bounds('new_mutation_without_oracle', 1, 'FAIL: fixture\n')
        self.assertFalse(accepted)
        self.assertIn('no expected assertion', error)
        self.assertNotIn('REJECTED:', output)
        self.assertEqual(calls, [])


if __name__ == '__main__':
    unittest.main(verbosity=2)
