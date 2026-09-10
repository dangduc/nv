#!/usr/bin/env python3
"""Run exact editor action-boundary methods with native text storage and views."""
from pathlib import Path
import hashlib, json, os, platform, subprocess
suite = Path(__file__).resolve().parent
repo = suite.parents[3]
out = repo / 'build/TypingReview/round3/torvalds'
out.mkdir(parents=True, exist_ok=True)
editor = (repo / 'Sources/Editor/LinkingEditor.m').read_text()
session = (repo / 'Sources/Editor/NVNoteEditingSession.m').read_text()
analysis = (repo / 'Sources/Editor/NVSourceAnalysis.m').read_text()
def method(source, signature):
    start = source.index(signature)
    return source[start:source.index('\n- (', start + 1)]
methods = '\n'.join(method(editor, sig) for sig in ['- (id)highlightLinkAtIndex:', '- (void)clickedOnLink:', '- (NSMenu *)menuForEvent:'])
(out / 'invalidate.inc').write_text(method(session, '- (void)sourceCharactersChanged:'))
(out / 'flags.inc').write_text(analysis[analysis.index('static char NVSourceLinksCurrentKey;'):analysis.index('NSArray *NVSourceLinkRuns')])
env = dict(os.environ, ASAN_OPTIONS='detect_leaks=0:halt_on_error=1', UBSAN_OPTIONS='halt_on_error=1:print_stacktrace=1')
def run(name, source):
    (out / 'methods.inc').write_text(source)
    command = ['xcrun', 'clang', '-arch', 'x86_64', '-fblocks', '-fno-objc-arc', '-O1', '-g', '-fsanitize=address,undefined', '-fno-omit-frame-pointer', '-Wno-deprecated-declarations', '-I', str(out), '-framework', 'Cocoa', str(suite / 'probe.m'), '-o', str(out / name)]
    build = subprocess.run(command, capture_output=True, text=True, timeout=45)
    (out / (name + '-compile.log')).write_text(build.stdout + build.stderr)
    if build.returncode: raise SystemExit(build.stderr)
    result = subprocess.run([str(out / name)], capture_output=True, text=True, env=env, timeout=45)
    (out / (name + '-output.txt')).write_text(result.stdout + result.stderr)
    print(name + ': ' + result.stdout + result.stderr, end='')
    return {'name': name, 'exit': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr, 'command': command}
runs = [run('production', methods)]
runs.append(run('negative-highlight', methods.replace('!totalLength || !NVSourceLinksAreCurrent([self textStorage])', '!totalLength')))
click_guard = 'if (!NVSourceLinksAreCurrent([self textStorage])) {'
assert methods.count(click_guard) == 1
runs.append(run('negative-click', methods.replace(click_guard, 'if (NO) {')))
menu_guard = 'if (!NVSourceLinksAreCurrent([self textStorage]))\n'
assert methods.count(menu_guard) == 1
runs.append(run('negative-menu', methods.replace(menu_guard, 'if (NO)\n')))
(out / 'methods.inc').write_text(methods)
passed = runs[0]['exit'] == 0 and all(r['exit'] != 0 and 'FAIL' in r['stderr'] for r in runs[1:])
report = {'head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip(), 'platform': platform.platform(), 'xcode': subprocess.check_output(['xcodebuild', '-version'], text=True).strip(), 'methods_sha256': hashlib.sha256(methods.encode()).hexdigest(), 'sanitizers': ['address', 'undefined'], 'passed': passed, 'runs': runs}
for destination in [suite, out]:
    (destination / 'results.json').write_text(json.dumps(report, indent=2) + '\n')
    (destination / 'output.txt').write_text('\n'.join(r['name'] + ':\n' + r['stdout'] + r['stderr'] for r in runs))
raise SystemExit(0 if passed else 1)
