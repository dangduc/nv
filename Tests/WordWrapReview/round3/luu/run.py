#!/usr/bin/env python3
"""Exercise frozen production with overflowing spaces and a long source token."""
import argparse,json,pathlib,subprocess
p=argparse.ArgumentParser();p.add_argument('--instrument',action='store_true');a=p.parse_args()
here=pathlib.Path(__file__).resolve().parent;repo=here.parents[3];out=repo/'build/WordWrapReview/round3/luu';out.mkdir(parents=True,exist_ok=True)
head='63911bf2c66d438f178b43a8b9e996787e29acc9';base='b6a5696'
(out/'typesetter.m').write_bytes(subprocess.check_output(['git','show',f'{head}:Sources/Editor/NVSourceTypesetter.m'],cwd=repo))
def method(rev):
 s=subprocess.check_output(['git','show',f'{rev}:Sources/Editor/LinkingEditor.m'],cwd=repo,text=True);start=s.index('- (NSUInteger)layoutManager:');end=s.index('{',start)+1;depth=1
 while depth:depth+=(s[end]=='{')-(s[end]=='}');end+=1
 return s[start:end]
hook=method(head);assert hook==method(base)
(out/'space-delegate.h').write_text('@interface SpaceDelegate:NSObject<NSLayoutManagerDelegate>\n@end\n@implementation SpaceDelegate\n'+hook+'\n@end\n')
common=['xcrun','clang','-arch','x86_64','-mmacosx-version-min=10.13','-O1','-fno-objc-arc','-Wno-deprecated-declarations','-I',str(out),'-I',str(repo/'Sources/Editor')]
obj=out/('counts.o'if a.instrument else'timing.o');subprocess.run(common+(['-include',str(here/'instrument.h')]if a.instrument else[])+['-c',str(out/'typesetter.m'),'-o',str(obj)],check=True)
binary=out/('probe-counts'if a.instrument else'probe-timing');subprocess.run(common+['-framework','Cocoa','-framework','CoreText',str(here/'probe.m'),str(obj),'-o',str(binary)],check=True)
result=here/('counts.json'if a.instrument else'timing.json');r=subprocess.run([str(binary),str(result),'counts'if a.instrument else'timing'],capture_output=True,text=True,timeout=90)
(out/('counts.log'if a.instrument else'timing.log')).write_text(r.stdout+r.stderr);print(r.stderr);r.check_returncode();report=json.loads(result.read_text())
for record in report['records']:
 if record['operation']=='cached-queries' and a.instrument:assert record['creates']==record['lineCreates']==record['suggests']==record['tokenAdvances']==0
print('PASS: production and pre-PR source, selections, and native insertion points match')
