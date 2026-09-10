#!/usr/bin/env python3
"""Check everyday Org meanings against the actual helper and renderer output."""
from html.parser import HTMLParser
from pathlib import Path
import hashlib
import json
import subprocess

here = Path(__file__).resolve().parent
repo = here.parents[3]
out = repo / 'build/OrgPreviewReview/round1/contrarian'
out.mkdir(parents=True, exist_ok=True)
helper = repo / 'ThirdParty/OrgPreview/nv-org-preview'
bundle = repo / 'build/DerivedData/Build/Products/Development/nvALT.app'
digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
assert digest(helper) == digest(bundle / 'Contents/Resources/nv-org-preview')

fixtures = {
    'tasks': '* TODO Work [1/3] :team:\n- [ ] Pending\n- [-] Partial\n- [X] Complete\n\n** DONE Review\nCafé 日本語 👩‍💻.\n',
    'literal': '* Notes\n=literal *stars*= and ~literal /slashes/~.\n\n#+BEGIN_EXAMPLE\n,* keep stars\n,#+END_SRC\nordinary <xml> & text\n#+END_EXAMPLE\n',
    'partial-block': '* TODO Draft\nBefore.\n#+BEGIN_SRC json\n{"new": "text"}\n',
    'partial-link': 'Before [[https://example.com][A label] after note text.\n',
    'web-link': '[[https://example.com/notes?a=1&b=2][Read the notes]]\n',
    'internal-links': '* TODO Release plan\n:PROPERTIES:\n:CUSTOM_ID: release-plan\n:END:\nPlan body.\n\n[[#release-plan][By custom ID]]\n[[*Release plan][By heading]]\n[[Release plan][By exact heading]]\n',
    'nested-lists': '- Parent\n  1. First child\n  2. Second child\n- Peer\n\n\n1. Ordered peer\n2. Final peer\n',
    'numbering': '1. [@20] First task\n2. Second task\n3. [@30] Third task\n4. Fourth task\n',
    'descriptions': '- Term :: A definition\n- Other :: More detail\n',
    'styled-link': '[[https://example.com][*Important* and /emphasized/]]\n',
}
for name, text in fixtures.items():
    (out / f'{name}.org').write_text(text)
input_hashes = {name: digest(out / f'{name}.org') for name in fixtures}

class HTML(HTMLParser):
    def __init__(self, source):
        super().__init__(convert_charrefs=True)
        self.ids, self.links, self.tags, self.text = set(), [], [], ''
        self.active_link = None
        self.feed(source)
    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        self.tags.append((tag, attrs))
        if 'id' in attrs: self.ids.add(attrs['id'])
        if tag == 'a':
            self.active_link = {'href': attrs.get('href'), 'text': ''}
            self.links.append(self.active_link)
    def handle_endtag(self, tag):
        if tag == 'a': self.active_link = None
    def handle_data(self, data):
        self.text += data
        if self.active_link is not None: self.active_link['text'] += data

checks = []
observations = []
def check(backend, name, result, detail):
    checks.append({'backend': backend, 'check': name, 'passed': bool(result), 'detail': detail})

def examine(backend, output):
    parsed = {name: HTML(text) for name, text in output.items()}
    text = parsed['tasks'].text
    check(backend, 'task labels and all checkbox states remain visible', all(x in text for x in ['TODO', 'DONE', '[1/3]', '[ ]', '[-]', '[X]', ':team:']), text)
    check(backend, 'Unicode remains visible', 'Café 日本語 👩‍💻.' in text, text)
    text = parsed['literal'].text
    check(backend, 'literal spans do not interpret embedded markers', 'literal *stars*' in text and 'literal /slashes/' in text, text)
    check(backend, 'example lines preserve literal contents and remove Org comma escapes', '* keep stars\n#+END_SRC\nordinary <xml> & text' in text and ',* keep' not in text, text)
    text = parsed['partial-block'].text
    check(backend, 'unfinished source block keeps its contents visible', 'Before.' in text and '#+BEGIN_SRC json' in text and '{"new": "text"}' in text, text)
    text = parsed['partial-link'].text
    check(backend, 'unfinished link stays literal', '[[https://example.com][A label]' in text and 'after note text.' in text and not parsed['partial-link'].links, text)
    link = parsed['web-link'].links
    check(backend, 'web link target and description remain exact', link == [{'href': 'https://example.com/notes?a=1&b=2', 'text': 'Read the notes'}], link)
    internal = parsed['internal-links']
    for label in ['By custom ID', 'By heading', 'By exact heading']:
        link = next(x for x in internal.links if x['text'] == label)
        href = link['href'] or ''
        check(backend, label + ' resolves within this document', href.startswith('#') and href[1:] in internal.ids, {'link': link, 'document_ids': sorted(internal.ids)})
    text = parsed['nested-lists'].text
    check(backend, 'nested lists keep every item visible', all(x in text for x in ['Parent', 'First child', 'Second child', 'Peer', 'Ordered peer', 'Final peer']), text)
    check(backend, 'nested and outer ordered lists remain separate structures', sum(tag == 'ol' for tag, attrs in parsed['nested-lists'].tags) == 2, parsed['nested-lists'].tags)
    # Record scope limitations separately from the concrete internal-link failure.
    for name in ['numbering', 'descriptions', 'styled-link']:
        observations.append({'backend': backend, 'fixture': name, 'HTML': output[name]})

output = {}
for name in fixtures:
    result = subprocess.run([str(helper)], input=(out / f'{name}.org').read_bytes(), capture_output=True, timeout=5)
    assert result.returncode == 0, result.stderr.decode()
    output[name] = result.stdout.decode()
    (out / f'{name}-helper.html').write_text(output[name])
examine('helper', output)

sdk = Path(subprocess.check_output(['xcrun', '--show-sdk-path'], text=True).strip())
binary = out / 'renderer-probe'
subprocess.run(['xcrun', 'clang', '-arch', 'x86_64', '-mmacosx-version-min=10.13', '-O2', '-fno-objc-arc', '-fblocks',
    '-framework', 'Foundation', '-lxml2', '-I', str(sdk / 'usr/include/libxml2'), '-I', str(repo / 'Sources/Preview'),
    str(repo / 'Sources/Preview/NVNoteContentSnapshot.m'), str(repo / 'Sources/Preview/NVMarkupRenderer.m'),
    str(here / 'renderer.m'), '-o', str(binary)], check=True)
result = subprocess.run([str(binary), str(bundle), str(out)], capture_output=True, text=True, timeout=20)
(here / 'renderer-output.txt').write_text(result.stdout + result.stderr)
assert result.returncode == 0, result.stdout + result.stderr
examine('renderer', {name: (out / f'{name}-renderer.html').read_text() for name in fixtures})
assert input_hashes == {name: digest(out / f'{name}.org') for name in fixtures}, 'the fixture source files remain unchanged'
(here / 'results.json').write_text(json.dumps({'checks': checks, 'scope_observations': observations}, ensure_ascii=False, indent=2) + '\n')
(here / 'metadata.json').write_text(json.dumps({
    'head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip(),
    'helper_sha256': digest(helper),
    'source_sha256': digest(repo / 'ThirdParty/OrgPreview/src/main.rs'),
    'renderer_sha256': digest(repo / 'Sources/Preview/NVMarkupRenderer.m'),
    'fixture_sha256': input_hashes,
    'scope': 'Ordinary supported Org text only. No application UI or live link navigation.'
}, indent=2) + '\n')
for item in checks: print(('PASS ' if item['passed'] else 'FAIL ') + item['backend'] + ': ' + item['check'])
failed = sum(not item['passed'] for item in checks)
print(f'{len(checks) - failed}/{len(checks)} expected-output checks passed; {failed} failed')
print(result.stdout)
raise SystemExit(bool(failed))
