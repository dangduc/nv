#!/usr/bin/env python3
"""Count live paragraph styles using the production getter and a per-call control."""
import json
from pathlib import Path
import subprocess

here=Path(__file__).resolve().parent
repo=here.parents[4]
out=repo/'build/WhitespaceWrapReview/fixes/round1/perf/style'
out.mkdir(parents=True,exist_ok=True)
source=(repo/'Sources/Preferences/GlobalPrefs.m').read_text()
start=source.index('- (NSDictionary*)noteBodyAttributes {')
end=source.index('\n- (void)setForegroundTextColor:',start)
shared=source[start:end]
start=shared.index('\tstatic NSParagraphStyle *sourceStyle;')
end=shared.index('\n\treturn noteBodyAttributes;',start)
before=shared[:start]+'''\tNSMutableParagraphStyle *sourceStyle = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
\t[sourceStyle setLineBreakMode:NSLineBreakByCharWrapping];
\t[(NSMutableDictionary *)noteBodyAttributes setObject:[[sourceStyle copy] autorelease] forKey:NSParagraphStyleAttributeName];
\t[sourceStyle release];'''+shared[end:]
results={}
for mode,getter in [('per-call-control',before),('shared-production',shared)]:
 generated=out/(mode+'.m')
 generated.write_text((here/'style-probe.m').read_text().replace('/*GETTER*/',getter))
 binary=out/mode
 subprocess.run(['xcrun','clang','-arch','x86_64','-O2','-fno-objc-arc','-framework','Cocoa',str(generated),'-o',str(binary)],check=True)
 run=subprocess.run(['arch','-x86_64',str(binary)],check=True,capture_output=True,text=True)
 results[mode]=json.loads(run.stdout)
assert results['per-call-control']['distinctLiveStyles']==10000
assert results['shared-production']['distinctLiveStyles']==1
assert results['shared-production']['styleObjectAllocationBytes']<results['per-call-control']['styleObjectAllocationBytes']
(here/'style-results.json').write_text(json.dumps(results,indent=2)+'\n')
print(json.dumps(results,indent=2))
print('PASS: constant immutable style and allocation-sensitive negative control')
