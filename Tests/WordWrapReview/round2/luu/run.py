#!/usr/bin/env python3
"""Compare frozen production cache lifetimes and short edit cost."""
import argparse,json,pathlib,subprocess
p=argparse.ArgumentParser();p.add_argument('--instrument',action='store_true');a=p.parse_args()
here=pathlib.Path(__file__).resolve().parent;repo=here.parents[3];out=repo/'build/WordWrapReview/round2/luu';out.mkdir(parents=True,exist_ok=True)
old='4b049709b2cecc6eac80514586ccacc119d12802';new='4c8f6b449504a50caa460d78efebd42b94beaba6'
for label,rev in [('old',old),('new',new)]:
 (out/f'{label}.m').write_bytes(subprocess.check_output(['git','show',f'{rev}:Sources/Editor/NVSourceTypesetter.m'],cwd=repo))
s=subprocess.check_output(['git','show',f'{new}:Sources/Editor/LinkingEditor.m'],cwd=repo,text=True);start=s.index('- (NSUInteger)layoutManager:');end=s.index('{',start)+1;depth=1
while depth:depth+=(s[end]=='{')-(s[end]=='}');end+=1
(out/'space-delegate.h').write_text('@interface SpaceDelegate:NSObject<NSLayoutManagerDelegate>\n@end\n@implementation SpaceDelegate\n'+s[start:end]+'\n@end\n')
common=['xcrun','clang','-arch','x86_64','-mmacosx-version-min=10.13','-O1','-fno-objc-arc','-Wno-deprecated-declarations','-I',str(out),'-I',str(repo/'Sources/Editor')]
objects=[]
for label in ['old','new']:
 obj=out/f'{label}-{"counts" if a.instrument else "timing"}.o';objects.append(str(obj));extra=[]
 if label=='old':extra+=['-DNVSourceTypesetter=NVPreviousTypesetter']
 if a.instrument:extra+=['-include',str(here/'instrument.h'),f'-DREVIEW_OLD={int(label=="old")}']
 subprocess.run(common+extra+['-c',str(out/f'{label}.m'),'-o',str(obj)],check=True)
binary=out/('probe-counts' if a.instrument else 'probe-timing');subprocess.run(common+['-framework','Cocoa','-framework','CoreText',str(here/'probe.m'),*objects,'-o',str(binary)],check=True)
result=here/('counts.json' if a.instrument else 'timing.json');r=subprocess.run([str(binary),str(result),'counts' if a.instrument else 'timing'],capture_output=True,text=True,timeout=45)
(out/('counts.log' if a.instrument else 'timing.log')).write_text(r.stdout+r.stderr);print(r.stderr);r.check_returncode();report=json.loads(result.read_text())
if a.instrument:
 for before,after in zip(report['old'],report['new']):
  assert before['state']==after['state']
  assert before['creates']==after['creates']
  assert before['snapshotChars']==after['snapshotChars']
  assert after['liveSnapshotChars']==0
  assert not after.get('measurePresent',False) and after.get('breakBytes',0)==0
 assert report['old'][2]['liveSnapshotChars']==16000
 assert report['old'][-2]['liveSnapshotChars']==192000
 assert report['new'][-2]['peakSnapshotChars']==16008
 print('PASS: each matched cache state has equal creation counts and no remaining completed cache')
