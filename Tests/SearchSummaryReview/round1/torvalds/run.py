#!/usr/bin/env python3
"""Compile exact production methods and run bounded native AppKit checks."""
import fcntl
import hashlib
import json
import re
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
OUT = REPO / 'build/SearchSummaryReview/round1/torvalds'
CHECKPOINT = '72c668cc5329ce6e48850377b35ec7d6d5b27d5b'
OUT.mkdir(parents=True, exist_ok=True)
PATHS = ['Sources/Browser/AppController_BrowserUI.m', 'Sources/Browser/AppController_Search.m',
         'Sources/Browser/NVBrowserSession.m', str((HERE / 'probe.m.in').relative_to(REPO)),
         str((HERE / 'run.py').relative_to(REPO))]


def hashes():
    return {path: hashlib.sha256((REPO / path).read_bytes()).hexdigest() for path in PATHS}


def method(source, signature):
    start = source.index(signature)
    # These three methods have no braces in strings or comments.
    opening = source.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


before = hashes()
for path in PATHS[:3]:
    committed = subprocess.check_output(['git', 'show', CHECKPOINT + ':' + path], cwd=REPO)
    assert hashlib.sha256(committed).hexdigest() == before[path], path + ' changed after checkpoint'
browser = (REPO / PATHS[0]).read_text()
search = (REPO / PATHS[1]).read_text()
methods = '\n'.join([
    method(browser, '- (void)updateSearchAffordance {'),
    method(browser, '- (IBAction)createNoteFromSearch:(id)sender {'),
    method(search, '- (IBAction)retrySearch:(id)sender {'),
])
template = (HERE / 'probe.m.in').read_text()
generated = template.replace('/* PRODUCTION_METHODS */', methods)
source = OUT / 'production.m'
source.write_text(generated)
mutation = generated.replace('[field setToolTip:status];', '[field setToolTip:[status length] ? status : [field toolTip]];')
assert mutation != generated
negative_source = OUT / 'negative.m'
negative_source.write_text(mutation)
record = {
    'checkpoint': CHECKPOINT,
    'head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=REPO, text=True).strip(),
    'source_sha256_before': before,
    'extracted_methods_sha256': hashlib.sha256(methods.encode()).hexdigest(),
    'generated_sha256': hashlib.sha256(generated.encode()).hexdigest(),
    'os': subprocess.check_output(['sw_vers'], text=True).strip(),
    'toolchain': subprocess.check_output(['xcodebuild', '-version'], text=True).strip(),
    'commands': [],
}


def run(name, command):
    result = subprocess.run(command, cwd=REPO, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (OUT / (name + '.log')).write_text(result.stdout)
    record['commands'].append({'name': name, 'argv': command, 'exit_code': result.returncode,
                               'passed_assertions': result.stdout.count('PASS:')})
    print(name, 'exit=' + str(result.returncode), flush=True)
    print(result.stdout, end='', flush=True)
    return result


flags = ['-fno-objc-arc', '-Wall', '-Werror', '-Werror=unguarded-availability', '-Werror=unguarded-availability-new']
compatibility = run('intel-10.13-compile', ['xcrun', 'clang', '-arch', 'x86_64', '-mmacosx-version-min=10.13',
                                        *flags, '-fsyntax-only', str(source)])
assert compatibility.returncode == 0
for name, input_source in [('production', source), ('negative', negative_source)]:
    result = run(name + '-compile', ['xcrun', 'clang', *flags, str(input_source), '-framework', 'Cocoa', '-o', str(OUT / name)])
    assert result.returncode == 0

lock = REPO / 'build/pr-review/gui.lock'
lock.parent.mkdir(parents=True, exist_ok=True)
print('Waiting for shared GUI lock for the two bounded AppKit runs.', flush=True)
with lock.open('a') as stream:
    fcntl.flock(stream, fcntl.LOCK_EX)
    positive = run('production-run', [str(OUT / 'production')])
    negative = run('negative-run', [str(OUT / 'negative')])

record['source_sha256_after'] = hashes()
record['changed_inputs'] = [path for path, digest in before.items() if record['source_sha256_after'][path] != digest]
record['positive_expected'] = positive.returncode == 0 and bool(re.search(r'TORVALDS_SUMMARY_PASS assertions=\d+ states=8', positive.stdout))
record['negative_expected'] = negative.returncode == 1 and 'FAIL: retry before delay: field tooltip' in negative.stdout
(OUT / 'results.json').write_text(json.dumps(record, indent=2) + '\n')
assert record['positive_expected'], 'Production did not pass all checks'
assert record['negative_expected'], 'Tooltip mutation did not produce its expected failure'
assert not record['changed_inputs'], record['changed_inputs']
print('PASS: production and tooltip negative control produced expected results.')
