#!/usr/bin/env python3
"""Bounded native R2 presentation responsiveness and shared-lane measurements."""
import argparse, hashlib, json
from pathlib import Path
import subprocess
ROOT=Path(__file__).resolve().parents[5]
HERE=Path(__file__).resolve().parent
p=argparse.ArgumentParser()
p.add_argument('--mode', choices=['dense','literal','positions'], action='append')
p.add_argument('--sanitize',action='store_true')
a=p.parse_args()
variant='sanitize' if a.sanitize else 'native'
OUT=ROOT/'build/FuzzySearchReview/round-2/luu'/variant
OUT.mkdir(parents=True,exist_ok=True)
production=['Sources/Search/NVFZF.c','ThirdParty/fzf-native/fzf.c','ThirdParty/fzf-native/utf8proc-2.10.0/utf8proc.c','Sources/Search/NVSearchQuery.m','Sources/Search/NVSearchCorpus.m','Sources/Search/NVSearchService.m']
tracked=[*production,'Sources/Search/NVSearchQuery.h','Sources/Search/NVSearchService.h','Sources/Browser/AppController_Search.m','Sources/Editor/LinkingEditor.m']
inputs={path:(ROOT/path).read_bytes() for path in tracked}
for path,prefixes,out in [('Sources/Browser/AppController_Search.m',['- (void)refreshSearchHighlights'],'refresh.inc'),('Sources/Editor/LinkingEditor.m',['- (void)removeHighlightedTerms','- (void)setSearchHighlightRanges:'],'editor.inc')]:
    source=inputs[path].decode(); chunks=[]
    for prefix in prefixes:
        start=source.index(prefix); chunks.append(source[start:source.index('\n}',start)+2])
    (OUT/out).write_text('\n'.join(chunks))
# Compile copied source bytes to prevent a concurrent repair from changing inputs.
for path in production:
    if path.endswith('.m'):
        content=inputs[path].decode()
        if path=='Sources/Search/NVSearchService.m':
            content='#include <time.h>\nextern void NVReviewPositionPhase(int phase, double milliseconds);\n'+content
            native='if (status == NVFZF_OK) status = nvfzf_positions_terms(_engine, (NVFZFCandidate){[bytes bytes], [bytes length]}, terms, [[search->query terms] count], work->cancel, &output);'
            mapping='NSArray *ranges = status == NVFZF_OK ? NVSearchMapRanges([snapshot candidate], output.offsets, output.count, work->cancel, &status) : nil;'
            assert content.count(native)==1 and content.count(mapping)==1
            content=content.replace(native,'double reviewNativeStart = (double)clock_gettime_nsec_np(CLOCK_UPTIME_RAW);\n        '+native+'\n        NVReviewPositionPhase(0, ((double)clock_gettime_nsec_np(CLOCK_UPTIME_RAW)-reviewNativeStart)/1e6);')
            content=content.replace(mapping,'double reviewMapStart = (double)clock_gettime_nsec_np(CLOCK_UPTIME_RAW);\n        '+mapping+'\n        NVReviewPositionPhase(1, ((double)clock_gettime_nsec_np(CLOCK_UPTIME_RAW)-reviewMapStart)/1e6);')
        (OUT/Path(path).name).write_text(content)
flags=['-arch','arm64','-g','-O1' if a.sanitize else '-O2','-DUTF8PROC_STATIC','-I'+str(OUT),'-I'+str(ROOT/'Sources/Search'),'-I'+str(ROOT/'ThirdParty/fzf-native')]
if a.sanitize: flags+=['-fsanitize=address,undefined','-fno-omit-frame-pointer']
objects=[]
for i,path in enumerate([*production,str(HERE.relative_to(ROOT)/'probe.m')]):
    src=OUT/Path(path).name if path in production and path.endswith('.m') else ROOT/path
    obj=OUT/f'{i}.o'
    lang=['-fblocks','-fno-objc-arc','-Wall','-Wextra','-Wno-unused-parameter'] if src.suffix=='.m' else ['-std=c11']
    subprocess.run(['xcrun','clang',*flags,*lang,'-c',str(src),'-o',str(obj)],check=True)
    objects.append(str(obj))
exe=OUT/'probe'
subprocess.run(['xcrun','clang',*flags,*objects,'-framework','Cocoa','-o',str(exe)],check=True)
results=[]
for mode in a.mode or ['dense','literal','positions']:
    result=subprocess.run([str(exe),mode],text=True,capture_output=True,timeout=35)
    print(mode,result.returncode,result.stdout,result.stderr,sep='\n',flush=True)
    results.append({'mode':mode,'exit_code':result.returncode,'stdout':result.stdout,'stderr':result.stderr})
record={'command':['python3',str(Path(__file__).relative_to(ROOT)),*(['--sanitize'] if a.sanitize else []),*sum((['--mode',m] for m in a.mode or []),[])], 'head':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(), 'toolchain':subprocess.check_output(['xcodebuild','-version'],text=True).strip(),'os':subprocess.check_output(['sw_vers'],text=True).strip(),'sha256':{p:hashlib.sha256(v).hexdigest() for p,v in inputs.items()}, 'timed_service_sha256':hashlib.sha256((OUT/'NVSearchService.m').read_bytes()).hexdigest(), 'fixture_sha256':hashlib.sha256((HERE/'probe.m').read_bytes()).hexdigest(),'results':results}
(HERE/(variant+'-results.json')).write_text(json.dumps(record,indent=2)+'\n')
assert all(r['exit_code']==0 for r in results),'fixture assertions failed'
