#!/usr/bin/env python3
"""Check bounded cleanup retries with AppKit, without a GUI application."""
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
SOURCE = ROOT / 'Sources/Editor/LinkingEditor.m'


def method(source, signature):
    start = source.index(signature)
    end = source.index('{', start) + 1
    depth = 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


before = hashlib.sha256(SOURCE.read_bytes()).hexdigest()
source = SOURCE.read_text()
signatures = [
    '- (void)invalidateSearchHighlights {',
    '- (void)removeHighlightedTerms {',
    '- (NSDictionary *)layoutManager:(NSLayoutManager *)manager shouldUseTemporaryAttributes:',
]
methods = '\n'.join(method(source, signature) for signature in signatures)
probe = (HERE / 'probe.m.in').read_text().replace('/* PRODUCTION_METHODS */', methods)
mutant = probe.replace('afterDelay:0.01', 'afterDelay:0')
assert mutant != probe, 'zero-delay mutation no longer applies'
results = {}
with tempfile.TemporaryDirectory(prefix='nv-cleanup-retry-') as directory:
    directory = Path(directory)
    for name, code in [('positive', probe), ('zero-delay-negative-control', mutant)]:
        path = directory / (name + '.m')
        path.write_text(code)
        binary = directory / name
        compile_result = subprocess.run(
            ['xcrun', 'clang', '-arch', 'x86_64', '-fno-objc-arc', '-O2',
             '-Wall', '-Wextra', '-Werror', '-Wno-unused-parameter',
             '-framework', 'Cocoa', str(path), '-o', str(binary)],
            text=True, capture_output=True)
        (HERE / (name + '-compile.txt')).write_text(compile_result.stdout + compile_result.stderr)
        compile_result.check_returncode()
        result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=10)
        output = result.stdout + result.stderr
        (HERE / (name + '.txt')).write_text(output)
        print(name + ':\n' + output, end='')
        results[name] = {'exit_code': result.returncode, 'probe_sha256': hashlib.sha256(code.encode()).hexdigest()}
        if name == 'positive':
            result.check_returncode()
        else:
            assert result.returncode == 1 and 'FAIL: character-edit retries have at least 10 ms delay' in output

after = hashlib.sha256(SOURCE.read_bytes()).hexdigest()
assert before == after, 'production changed during validation'
(HERE / 'manifest.json').write_text(json.dumps({
    'production_file': str(SOURCE.relative_to(ROOT)),
    'sha256_before': before, 'sha256_after': after,
    'production_methods': signatures, 'results': results,
    'platform': subprocess.check_output(['sw_vers'], text=True).strip(),
    'architecture': 'x86_64 through Rosetta',
    'limits': [
        'Real AppKit storage, layout manager, and run loop with an NSObject editor adapter.',
        'No browser, GUI app, personal notes, or macOS 13 session.',
        'Minimum scheduling delay is checked directly without a latency threshold.',
        'Native operation count uses elapsed time divided by 5 ms plus two callbacks, twice the allowed retry rate.'
    ],
}, indent=2) + '\n')
