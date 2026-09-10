#!/usr/bin/env python3
"""Audit saved evidence and source text; never execute a test runner or app."""
import ast
import hashlib
import json
from pathlib import Path
import re
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
REVIEW = ROOT / 'Tests/SourceBackspaceReview'
PRODUCTION = ['Sources/Browser/AppController.m', 'Sources/Browser/AppController_Search.m',
              'Sources/Editor/LinkingEditor.h', 'Sources/Editor/LinkingEditor.m']
inputs, checks = {}, []
def read(path):
    path = Path(path)
    if not path.is_absolute(): path = ROOT / path
    data = path.read_bytes()
    inputs[str(path.relative_to(ROOT))] = hashlib.sha256(data).hexdigest()
    return data.decode('utf-8', errors='replace')
def data(path): return json.loads(read(path))
def check(condition, label):
    checks.append({'passed': bool(condition), 'claim': label})
def hashes(): return {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in PRODUCTION}
def head(): return subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()

before, start = hashes(), head()
validation = data(REVIEW/'validation.json')
build_log = read('build/backspace-build.log')
check('** BUILD SUCCEEDED **' in build_log, 'Saved Development build log contains the successful-build marker')
final = validation['after_runner_correction']
case = validation['cases'][0]
app_results = data('build/SourceBackspace/results.json')
native = read('build/SourceBackspace/native.log')
final_native = read('build/backspace-final-native.log')
check(case['checks'] == final['source_backspace_checks'] == app_results['checks'] == 310,
      'Saved validation records agree on 310 copied-app checks')
check(case['native_exit'] == app_results['native_exit'] == 0 and case['passed'] and app_results['passed'],
      'Copied-app result records report successful native exit')
check(len(re.findall(r'PASS: ', native)) == 310 and 'SOURCE BACKSPACE PASSED (310 checks)' in native,
      'Saved native log contains 310 PASS records and the full-suite marker')
check(native in final_native, 'Final wrapper log includes the saved full native log')
check(case['binary_sha256'] == app_results['binary_sha256'], 'Copied-app binary identity agrees between saved records')
old = data('build/SourceBackspaceNegativeControl/results.json')
check(all(old[key] == validation['cases'][1][key] for key in
          ['binary_sha256','mode','native_exit','checks','original_range_exception','passed']),
      'Original-app control record agrees with validation.json')

bounds = read('build/backspace-final-bounds.log')
check('HIGHLIGHT BOUNDS PASSED: 134 checks' in bounds and final['highlight_bounds_checks'] == 134,
      'Final HighlightBounds log supports the 134-check claim')
for architecture in ['native','x86_64','sanitize']:
    log = read(f'build/FuzzySearchHighlightBounds/{architecture}/positive.log')
    check('HIGHLIGHT BOUNDS PASSED: 134 checks' in log,
          f'Saved {architecture} HighlightBounds log records 134 checks')
runner = read('Tests/FuzzySearch/HighlightBounds/run.py')
module = ast.parse(runner)
assignment = next(node for node in module.body if isinstance(node,ast.Assign)
                  and any(isinstance(target,ast.Name) and target.id == 'EXPECTED_MUTATION_FAILURES'
                          for target in node.targets))
expected = ast.literal_eval(assignment.value)
rejections = dict(re.findall(r'^REJECTED: (\w+) FAIL: (.+)$',bounds,re.MULTILINE))
check(len(expected) == final['expected_mutation_failures'] == 11 and rejections == expected,
      'All 11 saved rejection labels exactly match the current assertion map')
for name, label in expected.items():
    log = read(f'build/FuzzySearchHighlightBounds/native/{name}.log')
    check('FAIL: '+label in log.splitlines(), f'Saved {name} log contains its expected assertion line')
check('result.returncode != 1 or expected not in result.stderr.splitlines()' in runner,
      'Current bounds runner requires exit 1 and the exact expected stderr line')

source_runner = read('Tests/SourceBackspace/run.py')
check('environment.pop("NV_BACKSPACE_REPRO_ONLY", None)' in source_runner,
      'Current source runner text clears the inherited first-case-only switch')
check('result == 0 and full_completion' in source_runner and
      'SOURCE BACKSPACE PASSED \\([1-9][0-9]* checks\\)$' in source_runner,
      'Current source runner text requires successful exit and a full-suite marker')
oracle = data(REVIEW/'fixes/oracles/manifest.json')
unit = read(REVIEW/'fixes/oracles/output.txt')
check(oracle['tests'] == final['runner_unit_tests'] == 16 and 'Ran 16 tests' in unit and unit.rstrip().endswith('OK')
      and len(re.findall(r'^test_.* \.\.\. ok$',unit,re.MULTILINE)) == 16,
      'Saved unit output and manifests support 16 passing runner unit tests')
for path, recorded in oracle['source_sha256'].items():
    actual = hashlib.sha256(read(path).encode()).hexdigest()
    check(actual == recorded, f'Corrected runner evidence hash matches current {path}')

reviews = []
for path in sorted(REVIEW.glob('round[12]/*/manifest.json')):
    manifest = data(path)
    report = read(path.parent/'report.md')
    if 'production_hash_records' in manifest:
        records = [read(path.parent/name) for name in manifest['production_hash_records']]
        left = {line.split()[1]:line.split()[0] for line in records[0].splitlines()}
        right = {line.split()[1]:line.split()[0] for line in records[1].splitlines()}
    else:
        pairs = [('production_sha256_before','production_sha256_after'),
                 ('source_hashes_start','source_hashes_end'),('sha256_before','sha256_after')]
        left_key,right_key = next(pair for pair in pairs if pair[0] in manifest)
        left,right = manifest[left_key],manifest[right_key]
    check(all(left.get(name) == right.get(name) and name in left for name in PRODUCTION),
          f'{path.parent.relative_to(REVIEW)} records stable production hashes')
    final_match = all(left[name] == before[name] for name in PRODUCTION)
    reviews.append({'directory':str(path.parent.relative_to(ROOT)),
                    'matches_final_production':final_match,
                    'production_hashes':{name:left[name] for name in PRODUCTION},
                    'report_sha256':hashlib.sha256(report.encode()).hexdigest()})
check(len(reviews) == 12, 'Twelve completed first/second-round manifests and reports are present')
initial = {row['directory'].split('SourceBackspaceReview/')[1] for row in reviews if not row['matches_final_production']}
check(initial == {'round1/ousterhout','round1/luu','round1/kingsbury'},
      'Only the three documented initial reviews record the pre-retry production version')

# These are saved result markers, not newly executed checks.
markers = [
 ('round1/ousterhout/output.txt','checks=23 failures=0'),
 ('round1/luu/output.txt','checks=8216 failures=0'),
 ('round1/torvalds/candidate-output.txt','checks=51060 failures=0'),
 ('round1/contrarian-a/output.txt','Completed 16 checks.'),
 ('round1/contrarian-b/production.txt','matrices=7680 checks=39819 failures=0'),
 ('round2/ousterhout/candidate-output.txt','checks=26 failures=0'),
 ('round2/luu/production.txt','checks=1794 failures=0'),
 ('round2/torvalds/candidate-intel-output.txt','checks=43 failures=0'),
 ('round2/torvalds/candidate-native-sanitize-output.txt','checks=43 failures=0'),
 ('round2/kingsbury/positive.txt','PASS: 57 checks; 12 exhaustive schedules'),
 ('round2/contrarian-b/candidate-output.txt','checks=48 failures=0'),
]
for path, marker in markers:
    check(marker in read(REVIEW/path), f'Saved {path} supports its summarized count')
interleavings = data(REVIEW/'round1/kingsbury/interleavings.json')
check('13 native interleaving checks' in interleavings['output'] and interleavings['exit'] == 0,
      'Saved first-round state review supports 13 checks')
contrarian = read(REVIEW/'round2/contrarian-a/output.txt')
check(len(re.findall(r'^PASS:',contrarian,re.MULTILINE)) == 21,
      'Saved simulated-process review contains the reported 21 checks')

readme = read(REVIEW/'README.md')
suite_readme = read('Tests/SourceBackspace/README.md')
pr_draft = read('build/backspace-pr.md')
windows = read('build/backspace-windows.log')
aggregate = read('build/backspace-regressions.log')
baseline = data(REVIEW/'round1/kingsbury/baseline-results.json')
check('MULTIWINDOW TESTS PASSED (35 checks)' in windows and
      baseline['phases']['main']['checks'] == 35 and baseline['phases']['relaunch']['checks'] == 11
      and baseline['phases']['relaunch']['exit'] == -11 and baseline['baseline_cleanup_suppressed'],
      'Saved window evidence supports the qualified 35-main/11-relaunch baseline comparison')
check('FAIL: fuzzy workflow owns active disposable browser' in aggregate,
      'Saved aggregate log supports the stated fuzzy-browser focus failure')
for title, text in [('review README',readme),('suite README',suite_readme),('local PR draft',pr_draft)]:
    check('13.7.8' in text and ('untested' in text or 'do not establish' in text),
          f'{title} preserves the macOS 13.7.8 validation limit')
    check('search-field input' in text, f'{title} identifies the supplied search-background precondition')
check('simulated-process checks' in readme and 'no native runtime' in readme,
      'Review README distinguishes simulated-process and static evidence from native execution')
check('stops at' in pr_draft and 'library-switch crash' in pr_draft,
      'Local PR draft reports incomplete aggregate/window validation')
check('counts of distinct user workflows' in readme,
      'Review README warns that assertion totals do not count independent workflows')

# Compare source contents to the named production commit without running builds.
for name in PRODUCTION:
    recorded = subprocess.check_output(['git','show',validation['production_commit']+':'+name],cwd=ROOT)
    check(hashlib.sha256(recorded).hexdigest() == before[name],
          f'Current {name} matches the recorded production commit')
after = hashes()
check(after == before, 'Production source hashes remain unchanged during this artifact audit')
output = {'scope':'Static audit of saved artifacts and source text. No app or test runner execution.',
          'checks':checks,'reviews':reviews,'saved_validation_counts':final,
          'failed_checks':[row['claim'] for row in checks if not row['passed']]}
(HERE/'output.json').write_text(json.dumps(output,indent=2)+'\n')
manifest = {'head_start':start,'head_end':head(),'production_sha256_before':before,
            'production_sha256_after':after,'production_unchanged':before==after,
            'input_artifact_sha256':inputs,'audit_checks':len(checks),
            'audit_failures':len(output['failed_checks']),'native_executions':0,
            'limits':['Artifact consistency does not establish runtime behavior or log authenticity.',
                      'Only the local PR draft was read; this audit does not inspect live GitHub text.',
                      'Round-three work in progress was excluded from completeness claims.']}
(HERE/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps({'audit_checks':len(checks),'failures':output['failed_checks'],'native_executions':0},indent=2))
raise SystemExit(bool(output['failed_checks']))
