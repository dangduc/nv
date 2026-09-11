#!/usr/bin/env python3
"""Compare real-app geometry and reject movement of an already-fitting word."""
import argparse
import json
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--candidate-label', default='candidate')
args = parser.parse_args()
repo = Path(__file__).resolve().parents[4]
output = repo / 'build/WhitespaceWrapReview/round1/contrarian_ux'
base = json.loads((output / 'baseline-geometry.json').read_text())
changed = json.loads((output / f'{args.candidate_label}-geometry.json').read_text())
key = lambda row: (row['fixture'], row['font'], row['size'], row['width'], row.get('spaceCount'))
base = {key(row): row for row in base}
changed = {key(row): row for row in changed}
assert base.keys() == changed.keys()
line_ranges = lambda row: [(v['location'], v['length']) for v in row['lines']]
ordinary_changes = []
double_changes = []
for identity, candidate in changed.items():
    baseline = base[identity]
    if candidate['fixture'] == 'tabs-and-nbsp':
        assert candidate['lines'] == baseline['lines'], identity
    if candidate['fixture'] == 'ordinary-prose' and line_ranges(candidate) != line_ranges(baseline):
        ordinary_changes.append(identity)
    if candidate['fixture'] == 'double-spaced-prose' and line_ranges(candidate) != line_ranges(baseline):
        double_changes.append(identity)
    for hit in candidate.get('hitTests', []):
        assert hit['index'] == hit['hit'], (identity, hit)
control = ('native-space-key', 'Menlo-Regular', 18, 560, None)
candidate, baseline = changed[control], base[control]
regression = candidate['afterBeta']['y'] != candidate['beforeBeta']['y']
summary = {
    'native_runs': {label: json.loads((output / f'{label}.json').read_text()) for label in (args.candidate_label, 'baseline')},
    'layout_cases_per_app': len(changed),
    'ordinary_prose_reflows': len(ordinary_changes),
    'double_spaced_prose_reflows': len(double_changes),
    'tabs_nbsp_cases_unchanged': 12,
    'sampled_hit_tests_round_trip': True,
    'premature_word_wrap': regression,
    'candidate_native_key': candidate,
    'baseline_native_key': baseline,
    'arrow_observation': {label: rows[('arrow-observation', 'Menlo-Regular', 18, 560, None)]
                          for label, rows in ((args.candidate_label, changed), ('baseline', base))},
}
(output / f'{args.candidate_label}-comparison.json').write_text(json.dumps(summary, indent=2) + '\n')
print(json.dumps({k: summary[k] for k in ('layout_cases_per_app', 'ordinary_prose_reflows',
    'double_spaced_prose_reflows', 'premature_word_wrap')}, indent=2))
if regression:
    print('FAIL: the 40th trailing Space moves the already-fitting word beta onto the next visual line')
    raise SystemExit(1)
print('PASS: the appended space leaves the already-fitting word in place')
