#!/usr/bin/env python3
"""Exercise the bundled Org helper with disposable notes and bounded inputs."""
from pathlib import Path
from html.parser import HTMLParser
import shutil
import subprocess
import tempfile
from urllib.parse import unquote

repo = Path(__file__).resolve().parents[3]
fixtures = Path(__file__).resolve().parent
binary = repo / "ThirdParty/OrgPreview/nv-org-preview"
subprocess.run(["python3", str(repo / "Scripts/rebuild-org-preview.py"), "--verify-only"], check=True)
subprocess.run(["python3", str(fixtures / "rebuild-tests.py")], check=True)
with tempfile.TemporaryDirectory(prefix="nvalt-org-helper-") as temporary:
    work = Path(temporary)
    for name in ("core.org", "heading-links.org", "no-effects.org", "local-data.txt"):
        shutil.copy2(fixtures / name, work / name)
    def run(data):
        return subprocess.run([str(binary)], input=data, cwd=work, capture_output=True, timeout=15)
    p = run((work / "core.org").read_bytes())
    assert p.returncode == 0, p.stderr
    html = p.stdout.decode()
    checks = {
        'headline hierarchy': '<h1' in html and '<h2' in html,
        'TODO state': 'TODO' in html and 'DONE' in html,
        'priority': '[#A]' in html,
        'heading tags': 'work' in html,
        'bold': '<b>bold</b>' in html or '<strong>bold</strong>' in html,
        'italic': '<i>italic</i>' in html or '<em>italic</em>' in html,
        'underline': '<u>underline</u>' in html,
        'strike': '<s>strike</s>' in html or '<del>strike</del>' in html,
        'inline literal': 'literal</code>' in html and 'code</code>' in html,
        'Unicode': 'café 日本語 👩‍💻' in html,
        'checkbox state': ('[ ]' in html and '[X]' in html) or ('type="checkbox"' in html and 'checked' in html),
        'nested lists': html.count('<ul>') >= 2,
        'ordered list': '<ol>' in html,
        'table': '<table>' in html and '<thead>' in html and 'α' in html,
        'external link': 'href="https://example.com/notes"' in html,
        'relative file link': 'href="picture.png"' in html,
        'code block escaped': '&lt;tag&gt;' in html and '&amp;' in html,
        'example block': '* keep these stars\nliteral &lt;xml&gt; &amp; value' in html,
        'example comma removed': ',* keep these stars' not in html,
        'quote': '<blockquote>' in html and 'quoted text' in html,
    }

    class HeadingHTML(HTMLParser):
        def __init__(self, text):
            super().__init__(convert_charrefs=True)
            self.headings, self.links = [], {}
            self.link = None
            self.feed(text)
        def handle_starttag(self, tag, attrs):
            attrs = dict(attrs)
            if tag in ('h1', 'h2', 'h3', 'h4', 'h5', 'h6'):
                self.headings.append(attrs.get('id'))
            if tag == 'a':
                self.link = [attrs.get('href'), '']
        def handle_data(self, data):
            if self.link is not None:
                self.link[1] += data
        def handle_endtag(self, tag):
            if tag == 'a' and self.link is not None:
                self.links[self.link[1]] = self.link[0]
                self.link = None

    source = (work / 'heading-links.org').read_bytes()
    p = run(source)
    assert p.returncode == 0, p.stderr
    parsed = HeadingHTML(p.stdout.decode())
    def targets(label, index):
        href = parsed.links[label]
        return href.startswith('#') and unquote(href[1:]) == parsed.headings[index]
    checks['every heading has a unique anchor'] = len(parsed.headings) == 10 and all(parsed.headings) and len(set(parsed.headings)) == 10
    checks['forward starred heading link'] = targets('Forward starred', 1)
    checks['forward exact heading link'] = targets('Forward exact', 1)
    checks['CUSTOM_ID anchor preserved'] = parsed.headings[1] == 'release-plan' and targets('Custom ID', 1)
    checks['ID alias resolves preferred CUSTOM_ID'] = targets('ID alias', 1)
    checks['Unicode heading link'] = targets('Unicode heading', 2)
    checks['duplicate heading selects first'] = targets('Repeated heading', 3)
    checks['duplicate ID selects first'] = parsed.headings[3] == 'same' and targets('Repeated ID', 3)
    checks['ID property anchor preserved'] = parsed.headings[5] == 'only-id' and targets('ID property', 5)
    checks['Unicode ID is escaped and resolves'] = parsed.headings[6] == '予定&"item' and targets('Unicode ID', 6) and targets('Special fragment', 6) and '%E4%BA%88' in parsed.links['Unicode ID']
    checks['invalid ID gets a usable anchor'] = not any(c.isspace() for c in parsed.headings[7]) and targets('Invalid property', 7) and targets('Invalid ID fragment', 7)
    checks['later explicit ID reserved before generation'] = parsed.headings[8] == 'nv-org-heading-1' and parsed.headings[0] != parsed.headings[8]
    checks['unresolved headings retain targets'] = parsed.links['Unknown starred'] == '*Missing heading' and parsed.links['Unknown exact'] == 'Missing heading'
    checks['external URL remains external despite matching title'] = parsed.links['External'] == 'https://example.com/notes?a=1&b=2'
    checks['explicit file links retain paths'] = all(parsed.links[label] == path for label, path in [('Explicit file', 'Release plan'), ('Relative file', './Release plan'), ('Parent file', '../Release plan'), ('Absolute file', '/Release plan')])
    checks['undescribed heading links retain visible source'] = targets('*Release plan', 1) and targets('Release plan', 1)
    checks['anchors are deterministic'] = run(source).stdout == p.stdout
    checks['heading fixture source remains unchanged'] = (work / 'heading-links.org').read_bytes() == source

    p = run((work / "no-effects.org").read_bytes())
    checks["no code evaluation"] = not (work / "code-ran.txt").exists()
    checks["no include expansion"] = b"NV_ORG_INCLUDE_SENTINEL" not in p.stdout
    checks["unsupported include stays visible"] = b"#+INCLUDE:" in p.stdout and b"local-data.txt" in p.stdout
    checks["code remains visible"] = b"NV_ORG_CODE_SENTINEL" in p.stdout
    p = run(b"x" * (16 * 1024 * 1024 + 1))
    checks["16 MB input limit"] = p.returncode != 0 and b"source exceeds 16 MB" in p.stderr and not p.stdout
    p = run(b"&" * (7 * 1024 * 1024))
    checks["32 MB output limit"] = p.returncode != 0 and b"generated HTML exceeds 32 MB" in p.stderr and not p.stdout
    p = run(b"\xff")
    checks["invalid UTF-8 rejected"] = p.returncode != 0 and not p.stdout
    for name, passed in checks.items():
        print(("PASS " if passed else "FAIL ") + name)
    assert all(checks.values())
    print(str(len(checks)) + " Org helper checks passed")
