#!/usr/bin/env python3
"""Compare old/new production glyph methods during native edits and regeneration."""
import fcntl,hashlib,json,subprocess
from pathlib import Path
suite=Path(__file__).resolve().parent;repo=suite.parents[3]
output=repo/'build/WhitespaceWrapReview/round3/contrarian_platform';output.mkdir(parents=True,exist_ok=True)
reviewed='4b725372670afd5f5ecadf512deba8498336b2f0';baseline='072a6bc0f54a52603f8cedfbcacc17d0ab836a36'
def fragment(s):
 a=s.index('- (NSUInteger)layoutManager:(NSLayoutManager *)manager shouldGenerateGlyphs:');return s[a:s.index('\n}\n',a)+2]
def git_source(ref,path):return subprocess.check_output(['git','show',ref+':'+path],cwd=repo,text=True)
new=fragment((repo/'Sources/Editor/LinkingEditor.m').read_text());assert new==fragment(git_source(reviewed,'Sources/Editor/LinkingEditor.m'))
old=fragment(git_source(baseline,'Sources/Editor/LinkingEditor.m'))
s=(repo/'Sources/Preferences/GlobalPrefs.m').read_text();a=s.index('\tstatic NSParagraphStyle *sourceStyle;');style=s[a:s.index('\n}',a)]
assert hashlib.sha256(style.encode()).hexdigest()=='f9263d1675de92fde351aa09cc48fd9f7ff6a654332fa5df9644ff40d82fa993'
harness=output/'extracted-probe.m';harness.write_text((suite/'probe.m').read_text().replace('// EXTRACTED_OLD',old).replace('// EXTRACTED_NEW',new).replace('// EXTRACTED_STYLE',style))
binary=output/'probe-x86_64';subprocess.run(['xcrun','clang','-arch','x86_64','-mmacosx-version-min=13.0','-fno-objc-arc','-O1','-framework','Cocoa',str(harness),'-o',str(binary)],check=True)
with Path('/Users/duc/dev/nv/build/pr-review/gui.lock').open('a')as lock:
 fcntl.flock(lock,fcntl.LOCK_EX);r=subprocess.run([str(binary),str(output/'results.json')],text=True,capture_output=True,timeout=60)
print(r.stdout+r.stderr,end='');(output/'output.txt').write_text(r.stdout+r.stderr);r.check_returncode()
data=json.loads((output/'results.json').read_text());data.update(reviewed_head=reviewed,baseline_head=baseline,head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip(),old_method_sha256=hashlib.sha256(old.encode()).hexdigest(),new_method_sha256=hashlib.sha256(new.encode()).hexdigest(),style_block_sha256=hashlib.sha256(style.encode()).hexdigest(),architecture='x86_64',macOS=subprocess.check_output(['sw_vers','-productVersion'],text=True).strip())
for path in (output/'results.json',suite/'results.json'):path.write_text(json.dumps(data,indent=2)+'\n')
(suite/'output.txt').write_text(r.stdout+r.stderr)
print('native batch lengths:',data['newBatchLengths'])
