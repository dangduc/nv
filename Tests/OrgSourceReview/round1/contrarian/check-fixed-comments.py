#!/usr/bin/env python3
"""Check real comment presence and extent in the fixed native output."""
from pathlib import Path
import json

here = Path(__file__).resolve().parent
results = json.JSONDecoder().raw_decode((here / 'fixed-parser-output.txt').read_text())[0]
checks = 0
for case in results:
    expected = case['fixture'] in {'ordinary comment', 'comment after title', 'hashtag after comment'}
    assert case['comment'] == expected, case
    checks += 1
    for capture in case['captures']:
        if capture['kind'] == 'comment':
            assert '#travel' not in capture['text'], case
            checks += 1
output = f'PASS: {checks} independent comment-presence and comment-extent checks across the 18 fixed fixtures.\n'
(here / 'fixed-comment-checks.txt').write_text(output)
print(output, end='')
