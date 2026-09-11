#!/usr/bin/env python3
"""Observe production cleanup callbacks under AddressSanitizer and UBSan."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parents[4]
OUTPUT=ROOT/'build/WordWrapReview/round2/torvalds'
OUTPUT.mkdir(parents=True, exist_ok=True)
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--arch', choices=['arm64','x86_64'], default='arm64')
parser.add_argument('--negative-control', action='store_true')
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
    start=text.index('- (void)endParagraph {')
    end=text.index('\n}',start)+2
    assert '[super endParagraph];' in text[start:end] and '[self clearParagraphAnalysis];' in text[start:end]
    replacement='- (void)endParagraph {\n    [self clearParagraphAnalysis];\n    [super endParagraph];\n}'
    input_source=OUTPUT/'early-cleanup-negative.m'
    input_source.write_text(text[:start]+replacement+text[end:])
label=args.arch+('-negative' if args.negative_control else '')
binary=OUTPUT/f'probe-{label}'
subprocess.run(['xcrun','clang','-arch',args.arch,'-fno-objc-arc','-g','-O1',
    '-fsanitize=address,undefined','-fno-sanitize-recover=all','-fno-omit-frame-pointer',
    '-Wno-deprecated-declarations','-Wall','-Wextra','-Wno-unused-parameter',
    '-framework','Cocoa','-framework','CoreText','-I',str(OUTPUT),'-I',str(ROOT/'Sources/Editor'),
    str(Path(__file__).with_name('probe.m')),str(input_source),'-o',str(binary)],check=True)
environment=os.environ.copy()
environment['ASAN_OPTIONS']='detect_leaks=0:abort_on_error=1'
environment['UBSAN_OPTIONS']='halt_on_error=1:print_stacktrace=1'
evidence=OUTPUT/f'results-{label}.json'
run=subprocess.run(['arch',f'-{args.arch}',str(binary),str(evidence)],env=environment,
    capture_output=True,text=True,timeout=120)
(OUTPUT/f'run-{label}.log').write_text(run.stdout+run.stderr)
print(run.stdout+run.stderr,end='')
if args.negative_control:
    assert run.returncode==1 and 'native endParagraph returns before production cleanup' in run.stderr,run
    result={'status':'expected assertion failure','returncode':run.returncode}
else:
    run.check_returncode()
    result=json.loads(evidence.read_text())
result.update({'commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
    'productionSHA256':hashlib.sha256(production.read_bytes()).hexdigest(),
    'sanitizers':['address','undefined'],'architecture':args.arch})
if not args.negative_control:
    control=OUTPUT/f'retention-control-{args.arch}'
    subprocess.run(['xcrun','clang','-arch',args.arch,'-fno-objc-arc','-framework','Cocoa',
        '-framework','CoreText',str(Path(__file__).with_name('retention_control.m')),'-o',str(control)],check=True)
    result['attributedMarkerControls']=[json.loads(subprocess.check_output(
        ['arch',f'-{args.arch}',str(control)]+extra,text=True)) for extra in ([],['core-text'])]
(OUTPUT/f'summary-{label}.json').write_text(json.dumps(result,indent=2)+'\n')
