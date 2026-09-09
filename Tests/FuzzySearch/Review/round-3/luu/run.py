#!/usr/bin/env python3
"""Independent bounded Unicode scheduling review of production position work."""
import argparse,hashlib,json,os
from pathlib import Path
import subprocess
ROOT=Path(__file__).resolve().parents[5]
HERE=Path(__file__).resolve().parent
parser=argparse.ArgumentParser()
parser.add_argument('--sanitize',action='store_true')
parser.add_argument('--mutation',choices=['no-yield'])
a=parser.parse_args()
variant=('sanitize' if a.sanitize else 'native')+('-'+a.mutation if a.mutation else '')
OUT=ROOT/'build/FuzzySearchReview/round-3/luu'/variant
OUT.mkdir(parents=True,exist_ok=True)
paths=['Sources/Search/NVFZF.c','ThirdParty/fzf-native/fzf.c','ThirdParty/fzf-native/utf8proc-2.10.0/utf8proc.c','Sources/Search/NVSearchQuery.m','Sources/Search/NVSearchCorpus.m','Sources/Search/NVSearchService.m']
tracked=[*paths,'Sources/Search/NVSearchQuery.h','Sources/Search/NVSearchService.h','Sources/Editor/LinkingEditor.m']
inputs={p:(ROOT/p).read_bytes() for p in tracked}
head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
service=inputs['Sources/Search/NVSearchService.m'].decode()
if a.mutation:
    limit='sequences == 4096 ||\n            (!(sequences & 63) && CFAbsoluteTimeGetCurrent() >= deadline)'
    assert service.count(limit)==1
    service=service.replace(limit,'sequences == NSUIntegerMax ||\n            (NO && CFAbsoluteTimeGetCurrent() >= deadline)')
(OUT/'NVSearchService.m').write_text(service)
editor=inputs['Sources/Editor/LinkingEditor.m'].decode();methods=[]
for prefix in ['- (void)removeHighlightedTerms','- (void)setSearchHighlightRanges:']:
    start=editor.index(prefix);methods.append(editor[start:editor.index('\n}',start)+2])
(OUT/'editor.inc').write_text('\n'.join(methods))
flags=['-arch','arm64','-g','-O1' if a.sanitize else '-O2','-DUTF8PROC_STATIC','-I'+str(OUT),'-I'+str(ROOT/'Sources/Search'),'-I'+str(ROOT/'ThirdParty/fzf-native')]
if a.sanitize:flags+=['-fsanitize=address,undefined','-fno-omit-frame-pointer']
objects=[]
for i,p in enumerate([*paths,str(HERE.relative_to(ROOT)/'probe.m')]):
    src=OUT/'NVSearchService.m' if p=='Sources/Search/NVSearchService.m' else ROOT/p
    obj=OUT/f'{i}.o'
    language=['-fblocks','-fno-objc-arc','-Wall','-Wextra','-Wno-unused-parameter','-Werror'] if src.suffix=='.m' else ['-std=c11']
    subprocess.run(['xcrun','clang',*flags,*language,'-c',str(src),'-o',str(obj)],check=True)
    objects.append(str(obj))
exe=OUT/'probe'
subprocess.run(['xcrun','clang',*flags,*objects,'-framework','Cocoa','-o',str(exe)],check=True)
result=subprocess.run([str(exe)],capture_output=True,text=True,timeout=25,env=dict(os.environ,UBSAN_OPTIONS='halt_on_error=1'))
print(result.stdout,end='');print(result.stderr,end='')
record={'head':head,'stable_service_commit':'11f571f','arch':'arm64','sanitize':a.sanitize,'mutation':a.mutation,'exit_code':result.returncode,'stdout':result.stdout,'stderr':result.stderr,'source_sha256':{p:hashlib.sha256(b).hexdigest() for p,b in inputs.items()},'compiled_service_sha256':hashlib.sha256(service.encode()).hexdigest(),'fixture_sha256':hashlib.sha256((HERE/'probe.m').read_bytes()).hexdigest(),'command':['python3',str(Path(__file__).relative_to(ROOT)),*(['--sanitize'] if a.sanitize else []),*(['--mutation',a.mutation] if a.mutation else [])],'os':subprocess.check_output(['sw_vers'],text=True).strip(),'xcode':subprocess.check_output(['xcodebuild','-version'],text=True).strip()}
(HERE/(variant+'-results.json')).write_text(json.dumps(record,indent=2)+'\n')
raise SystemExit(result.returncode)
