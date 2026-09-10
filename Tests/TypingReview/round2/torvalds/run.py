#!/usr/bin/env python3
"""Differential native-storage test of exact production link publication, with sanitizers."""
from pathlib import Path
import hashlib
import json
import os
import platform
import subprocess
suite=Path(__file__).resolve().parent
repo=suite.parents[3]
out=repo/'build/TypingReview/round2/torvalds'
out.mkdir(parents=True,exist_ok=True)
session=(repo/'Sources/Editor/NVNoteEditingSession.m').read_text()
start=session.index('- (void)sourceAnalysis:(NVSourceAnalysis *)analysis didFinish:')
publication=session[start:session.index('\n- (',start+1)]
analysis=(repo/'Sources/Editor/NVSourceAnalysis.m').read_text()
(out/'flags.inc').write_text(analysis[analysis.index('static char NVSourceLinksCurrentKey;'):analysis.index('NSArray *NVSourceLinkRuns')])
command=['xcrun','clang','-arch','x86_64','-mmacosx-version-min=10.13','-fblocks','-fno-objc-arc','-O1','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer','-Wno-deprecated-declarations','-I',str(repo/'Sources/Editor'),'-I',str(out),'-framework','Cocoa',str(suite/'probe.m'),'-o',str(out/'probe')]
env=dict(os.environ,ASAN_OPTIONS='detect_leaks=0:halt_on_error=1',UBSAN_OPTIONS='halt_on_error=1:print_stacktrace=1')
def run(body,name):
    (out/'publication.inc').write_text(body)
    executable=out/(name+'-probe')
    build=subprocess.run(command[:-1]+[str(executable)],capture_output=True,text=True,timeout=45)
    (out/(name+'-compile.log')).write_text(build.stdout+build.stderr)
    if build.returncode: raise SystemExit(build.stderr)
    result=subprocess.run([str(executable)],capture_output=True,text=True,env=env,timeout=60)
    (out/(name+'-output.txt')).write_text(result.stdout+result.stderr)
    print(name+': '+result.stdout+result.stderr,end='')
    return result
result=run(publication,'production')
removals='''        for (NSDictionary *link in removals)
            [textStorage removeAttribute:NSLinkAttributeName range:[link[@"range"] rangeValue]];
'''
assert publication.count(removals)==1
broken=publication.replace(removals,'').replace('        [textStorage endEditing];',removals+'        [textStorage endEditing];')
negative=run(broken,'negative-control-removals-last')
(out/'publication.inc').write_text(publication)
report={'head':subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip(),'platform':platform.platform(),'xcode':subprocess.check_output(['xcodebuild','-version'],text=True).strip(),'publication_sha256':hashlib.sha256(publication.encode()).hexdigest(),'production_exit':result.returncode,'negative_control_exit':negative.returncode,'sanitizers':['address','undefined'],'commands':[command[:-1]+[str(out/(name+'-probe'))] for name in ['production','negative-control-removals-last']],'passed':result.returncode==0 and negative.returncode!=0 and 'FAIL case=1' in negative.stderr}
(out/'results.json').write_text(json.dumps(report,indent=2)+'\n')
(suite/'output.txt').write_text('Production:\n'+result.stdout+result.stderr+'\nNegative control (removals after additions):\n'+negative.stdout+negative.stderr)
(suite/'results.json').write_text(json.dumps(report,indent=2)+'\n')
raise SystemExit(0 if report['passed'] else 1)
