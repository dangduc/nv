#!/usr/bin/env python3
"""Exercise production null-return fallback with bounded Core Text hooks."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parents[4]
HERE=Path(__file__).resolve().parent
OUTPUT=ROOT/'build/WordWrapReview/round3/torvalds'
OUTPUT.mkdir(parents=True,exist_ok=True)
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--arch',choices=['arm64','x86_64'],default='arm64')
parser.add_argument('--negative-control',action='store_true')
args=parser.parse_args()
source=(ROOT/'Sources/Editor/LinkingEditor.m').read_text()
start=source.index('- (NSUInteger)layoutManager:')
opening=source.index('{',start)
depth,end=1,opening+1
while depth:
    depth+=(source[end]=='{')-(source[end]=='}')
    end+=1
(OUTPUT/'production-space-delegate.h').write_text(
    '@interface SpaceDelegate : NSObject <NSLayoutManagerDelegate>\n@end\n'
    '@implementation SpaceDelegate\n'+source[start:end]+'\n@end\n')
production=ROOT/'Sources/Editor/NVSourceTypesetter.m'
input_source=production
if args.negative_control:
    text=production.read_text()
    assert text.count('CFRelease(line);')==1
    input_source=OUTPUT/'missing-line-release-negative.m'
    input_source.write_text(text.replace('CFRelease(line);','/* Test-only omitted line release. */'))
label=args.arch+('-negative' if args.negative_control else '')
flags=['xcrun','clang','-arch',args.arch,'-fno-objc-arc','-g','-O1',
    '-fsanitize=address,undefined','-fno-sanitize-recover=all','-fno-omit-frame-pointer',
    '-Wno-deprecated-declarations','-Wall','-Wextra','-Wno-unused-parameter',
    '-I',str(HERE),'-I',str(OUTPUT),'-I',str(ROOT/'Sources/Editor')]
obj=OUTPUT/f'production-{label}.o'
subprocess.run(flags+['-DREVIEW_PRODUCTION_CALLS','-include',str(HERE/'fault_hooks.h'),
    '-c',str(input_source),'-o',str(obj)],check=True)
binary=OUTPUT/f'probe-{label}'
subprocess.run(flags+['-framework','Cocoa','-framework','CoreText',str(HERE/'probe.m'),
    str(HERE/'fault_hooks.m'),str(obj),'-o',str(binary)],check=True)
environment=os.environ.copy()
environment['ASAN_OPTIONS']='detect_leaks=0:abort_on_error=1'
environment['UBSAN_OPTIONS']='halt_on_error=1:print_stacktrace=1'
evidence=OUTPUT/f'results-{label}.json'
run=subprocess.run(['arch',f'-{args.arch}',str(binary),str(evidence)],env=environment,
    capture_output=True,text=True,timeout=120)
(OUTPUT/f'run-{label}.log').write_text(run.stdout+run.stderr)
print(run.stdout+run.stderr,end='')
if args.negative_control:
    assert run.returncode==1 and 'every created Core Text object receives a production release' in run.stderr,run
    result={'status':'expected ownership assertion failure','returncode':run.returncode}
else:
    run.check_returncode()
    result=json.loads(evidence.read_text())
result.update({'commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
    'productionSHA256':hashlib.sha256(production.read_bytes()).hexdigest(),
    'sanitizers':['address','undefined'],'architecture':args.arch})
(OUTPUT/f'summary-{label}.json').write_text(json.dumps(result,indent=2)+'\n')
