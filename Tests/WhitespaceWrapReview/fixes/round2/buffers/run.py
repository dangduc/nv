#!/usr/bin/env python3
"""Compare exact old/new glyph methods with guarded inputs and native layout."""
import fcntl
import json
from pathlib import Path
import subprocess

here=Path(__file__).resolve().parent
repo=here.parents[4]
out=repo/'build/WhitespaceWrapReview/fixes/round2/buffers'
out.mkdir(parents=True,exist_ok=True)
def method(source):
 start=source.index('- (NSUInteger)layoutManager:(NSLayoutManager *)manager shouldGenerateGlyphs:')
 end=source.index('\n- (NSColor *)sourceColorForCapture:',start)
 return source[start:end]
old=method(subprocess.check_output(['git','show','072a6bc0f54a52603f8cedfbcacc17d0ab836a36:Sources/Editor/LinkingEditor.m'],cwd=repo,text=True))
new=method((repo/'Sources/Editor/LinkingEditor.m').read_text())
generated=(here/'probe.m').read_text().replace('/*OLD*/',old).replace('/*NEW*/',new)
(out/'generated.m').write_text(generated)
binary=out/'probe'
subprocess.run(['xcrun','clang','-arch','x86_64','-O1','-g','-fsanitize=address,undefined',
 '-fno-omit-frame-pointer','-fno-objc-arc','-Wno-deprecated-declarations','-framework','Cocoa',
 str(out/'generated.m'),'-o',str(binary)],check=True)
results={}
for mode in ['units','native']:
 if mode=='native':
  lock=open('/Users/duc/dev/nv/build/pr-review/gui.lock','a');fcntl.flock(lock,fcntl.LOCK_EX)
 try:
  run=subprocess.run(['arch','-x86_64',str(binary),mode,str(out/(mode+'.json'))],capture_output=True,text=True,check=True,timeout=120)
 finally:
  if mode=='native':lock.close()
 (out/(mode+'.log')).write_text(run.stdout+run.stderr);print(run.stdout+run.stderr,end='')
 results[mode]=json.loads((out/(mode+'.json')).read_text())
(here/'results.json').write_text(json.dumps(results,indent=2)+'\n')
print('PASS: extracted production methods, ASan/UBSan, guarded buffers, allocation failure, and native equivalence')
