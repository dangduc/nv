#!/usr/bin/env python3
"""Measure ordinary Org notes through the shipped converter and actual renderer."""
from pathlib import Path
import hashlib
import json
import platform
import re
import statistics
import subprocess
import time

here = Path(__file__).resolve().parent
repo = here.parents[3]
out = repo / 'build/OrgPreviewReview/round1/luu'
out.mkdir(parents=True, exist_ok=True)
helper = repo / 'ThirdParty/OrgPreview/nv-org-preview'
bundle = repo / 'build/DerivedData/Build/Products/Development/nvALT.app'
bundled = bundle / 'Contents/Resources/nv-org-preview'
digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
assert digest(helper) == digest(bundled), 'the app must contain the reviewed converter'

def notebook(count):
    lines = ['#+TITLE: Engineering journal\n\n']
    for i in range(count):
        lines.append(f'''* TODO [#B] Release {i} :work:planning:
:PROPERTIES:
:CUSTOM_ID: release-{i}
:END:
The *source editor* needs /review/. Keep =literal markers= and ~code~ visible.
Café 日本語 👩‍💻 records the discussion and _next step_.

- [ ] Read the comments
  - [X] Collect timings
  - [ ] Review memory
- [X] Retain ordinary notes

| Component | Status |
|-----------+--------|
| Source    | Ready  |
| Preview   | Review |

See [[https://example.com/notes][release notes]] and [[file:agenda.org][agenda]].

#+BEGIN_SRC json
{{"enabled": true, "text": "<tag> & value"}}
#+END_SRC

** DONE Discussion
#+BEGIN_QUOTE
The implementation retains source text.
#+END_QUOTE

''')
    lines.append('END_OF_NOTE_SENTINEL\n')
    return ''.join(lines).encode()

helper_results = []
for sections in [12, 144, 1536]:
    source = notebook(sections)
    path = out / f'notebook-{sections}.org'
    path.write_bytes(source)
    samples = []
    for trial in range(3):
        start = time.perf_counter()
        result = subprocess.run(['/usr/bin/time', '-l', str(helper)], input=source, capture_output=True, timeout=15)
        elapsed = (time.perf_counter() - start) * 1000
        assert result.returncode == 0, result.stderr.decode()
        html = result.stdout.decode()
        assert html.count('<h1') == sections and html.count('<h2') == sections
        assert html.count('org-todo') == 2 * sections and 'END_OF_NOTE_SENTINEL' in html
        assert 'café' not in html and 'Café 日本語 👩‍💻' in html
        assert '<table>' in html and '&lt;tag&gt; &amp; value' in html
        rss = int(re.search(rb'(\d+)\s+maximum resident set size', result.stderr)[1])
        samples.append({'wall_ms': elapsed, 'max_rss_bytes': rss, 'output_bytes': len(result.stdout)})
    entry = {'sections': sections, 'input_bytes': len(source), 'samples': samples,
             'median_ms': statistics.median(s['wall_ms'] for s in samples)}
    helper_results.append(entry)
    print('helper', json.dumps(entry), flush=True)
(here / 'helper-output.json').write_text(json.dumps(helper_results, indent=2) + '\n')

sdk = Path(subprocess.check_output(['xcrun', '--show-sdk-path'], text=True).strip())
binary = out / 'renderer-probe'
subprocess.run(['xcrun', 'clang', '-arch', 'x86_64', '-mmacosx-version-min=10.13', '-O2',
               '-fno-objc-arc', '-fblocks', '-framework', 'Foundation', '-lxml2',
               '-I', str(sdk / 'usr/include/libxml2'), '-I', str(repo / 'Sources/Preview'),
               str(repo / 'Sources/Preview/NVNoteContentSnapshot.m'),
               str(repo / 'Sources/Preview/NVMarkupRenderer.m'), str(here / 'renderer.m'),
               '-o', str(binary)], check=True)
lines = []
for sections in [12, 144, 1536]:
    result = subprocess.run([str(binary), str(bundle), str(out / f'notebook-{sections}.org'), 'render'],
                            capture_output=True, text=True, timeout=30)
    lines.append(result.stdout + result.stderr)
    print(lines[-1], flush=True)
    result.check_returncode()
for mode in ['cancel', 'timeout', 'input-limit']:
    result = subprocess.run([str(binary), str(bundle), str(out / 'notebook-1536.org'), mode],
                            capture_output=True, text=True, timeout=30)
    lines.append(result.stdout + result.stderr)
    print(lines[-1], flush=True)
    result.check_returncode()
(here / 'renderer-output.txt').write_text('\n'.join(lines))
paths = ['Sources/Preview/NVMarkupRenderer.m', 'Sources/Preview/NVNoteContentSnapshot.m',
         'ThirdParty/OrgPreview/src/main.rs', 'ThirdParty/OrgPreview/Cargo.lock',
         'ThirdParty/OrgPreview/nv-org-preview']
metadata = {'head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip(),
            'base': 'f3a8abb2b7942d06ec33af64b4946cfd1b6db163', 'host': platform.platform(),
            'xcode': subprocess.check_output(['xcodebuild', '-version'], text=True).strip(),
            'sha256': {p: digest(repo / p) for p in paths},
            'app_helper_sha256': digest(bundled),
            'execution': 'Intel helper and Foundation renderer through Rosetta; no WebKit or app UI loaded'}
(here / 'metadata.json').write_text(json.dumps(metadata, indent=2) + '\n')
