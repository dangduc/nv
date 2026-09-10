#!/usr/bin/env python3
"""Exercise the bundled Org helper with disposable notes and bounded inputs."""
from pathlib import Path
import shutil
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[3]
fixtures = Path(__file__).resolve().parent
binary = repo / "ThirdParty/OrgPreview/nv-org-preview"
subprocess.run(["python3", str(repo / "Scripts/rebuild-org-preview.py"), "--verify-only"], check=True)
with tempfile.TemporaryDirectory(prefix="nvalt-org-helper-") as temporary:
    work = Path(temporary)
    for name in ("core.org", "no-effects.org", "local-data.txt"):
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
