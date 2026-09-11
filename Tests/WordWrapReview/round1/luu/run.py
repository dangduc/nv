#!/usr/bin/env python3
"""Measure production typesetting for bounded layout and edits; no windows or notes."""
import argparse,json,pathlib,subprocess
p=argparse.ArgumentParser();p.add_argument('--instrument',action='store_true');a=p.parse_args()
here=pathlib.Path(__file__).resolve().parent;repo=here.parents[3]
out=repo/'build/WordWrapReview/round1/luu';out.mkdir(parents=True,exist_ok=True)
s=(repo/'Sources/Editor/LinkingEditor.m').read_text();start=s.index('- (NSUInteger)layoutManager:');opening=s.index('{',start);end=opening+1;depth=1
while depth:
 depth+=(s[end]=='{')-(s[end]=='}');end+=1
(out/'space-delegate.h').write_text('@interface SpaceDelegate:NSObject<NSLayoutManagerDelegate>\n@end\n@implementation SpaceDelegate\n'+s[start:end]+'\n@end\n')
common=['xcrun','clang','-arch','x86_64','-mmacosx-version-min=10.13','-O1','-fno-objc-arc','-Wno-deprecated-declarations','-I',str(out),'-I',str(repo/'Sources/Editor')]
obj=out/('typesetter-instrument.o' if a.instrument else 'typesetter.o')
subprocess.run(common+(['-include',str(here/'instrument.h')] if a.instrument else [])+['-c',str(repo/'Sources/Editor/NVSourceTypesetter.m'),'-o',str(obj)],check=True)
binary=out/('probe-instrument' if a.instrument else 'probe')
subprocess.run(common+['-framework','Cocoa','-framework','CoreText',str(here/'probe.m'),str(obj),'-o',str(binary)],check=True)
result=here/('instrument-results.json' if a.instrument else 'results.json')
r=subprocess.run([str(binary),str(result),'instrument' if a.instrument else 'timing'],capture_output=True,text=True,timeout=180)
(out/('instrument.log' if a.instrument else 'timing.log')).write_text(r.stdout+r.stderr)
print(r.stderr);r.check_returncode();json.loads(result.read_text())
