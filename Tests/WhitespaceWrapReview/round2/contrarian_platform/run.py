#!/usr/bin/env python3
"""Check current character-wrap policy and glyph adjustment on native Unicode layout."""
import fcntl,hashlib,json,subprocess
from pathlib import Path
suite=Path(__file__).resolve().parent
repo=suite.parents[3]
output=repo/'build/WhitespaceWrapReview/round2/contrarian_platform';output.mkdir(parents=True,exist_ok=True)
reviewed='072a6bc0f54a52603f8cedfbcacc17d0ab836a36'
s=(repo/'Sources/Editor/LinkingEditor.m').read_text();a=s.index('- (NSUInteger)layoutManager:(NSLayoutManager *)manager shouldGenerateGlyphs:');glyph=s[a:s.index('\n}\n',a)+2]
s=(repo/'Sources/Preferences/GlobalPrefs.m').read_text();a=s.index('\tstatic NSParagraphStyle *sourceStyle;');style=s[a:s.index('\n}',a)]
assert hashlib.sha256(glyph.encode()).hexdigest()=='7a3c15d7e02a071f3f1bab9018e360f6b92decc7c48bb7ecd49189c179a188ef'
assert hashlib.sha256(style.encode()).hexdigest()=='f9263d1675de92fde351aa09cc48fd9f7ff6a654332fa5df9644ff40d82fa993'
harness=output/'extracted-probe.m';harness.write_text((suite/'probe.m').read_text().replace('// EXTRACTED_STYLE_BLOCK',style).replace('// EXTRACTED_GLYPH_METHOD',glyph))
binary=output/'probe-x86_64'
subprocess.run(['xcrun','clang','-arch','x86_64','-mmacosx-version-min=13.0','-fno-objc-arc','-O1','-framework','Cocoa',str(harness),'-o',str(binary)],check=True)
with Path('/Users/duc/dev/nv/build/pr-review/gui.lock').open('a')as lock:
 fcntl.flock(lock,fcntl.LOCK_EX)
 run=subprocess.run([str(binary),str(output/'results.json')],text=True,capture_output=True,timeout=60)
print(run.stdout+run.stderr,end='');(output/'output.txt').write_text(run.stdout+run.stderr);run.check_returncode()
r=json.loads((output/'results.json').read_text());r.update(reviewed_head=reviewed,head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip(),architecture='x86_64',macOS=subprocess.check_output(['sw_vers','-productVersion'],text=True).strip(),glyph_method_sha256=hashlib.sha256(glyph.encode()).hexdigest(),style_block_sha256=hashlib.sha256(style.encode()).hexdigest())
for path in (output/'results.json',suite/'results.json'):path.write_text(json.dumps(r,indent=2)+'\n')
(suite/'output.txt').write_text(run.stdout+run.stderr)
for c in r['cases']:
 if c['currentSplitOffsets']or c['currentInteriorHits']:print('OBSERVE',c)
