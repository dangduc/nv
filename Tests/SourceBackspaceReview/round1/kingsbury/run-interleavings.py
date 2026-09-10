#!/usr/bin/env python3
"""Compile actual candidate methods against native TextKit and deterministic owner schedules."""
import hashlib, json, subprocess, sys
from pathlib import Path
HERE=Path(__file__).resolve().parent; ROOT=HERE.parents[3]
paths=['Sources/Editor/LinkingEditor.m','Sources/Browser/AppController_Search.m']
def method(path,name):
    source=(ROOT/path).read_text();start=source.index(name);return source[start:source.index('\n}',start)+2]
(HERE/'editor.inc').write_text('\n'.join(method(paths[0],n) for n in ['- (void)invalidateSearchHighlights','- (void)removeHighlightedTerms','- (void)setSearchHighlightRanges:']))
(HERE/'observer.inc').write_text(method(paths[1],'- (void)searchSourceStorageWillProcessEditing:'))
manifest={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths}
binary=ROOT/'build/SourceBackspaceReview-kingsbury-interleavings'
subprocess.run(['xcrun','clang','-fno-objc-arc','-Wall','-Wextra','-Werror','-Wno-unused-parameter','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer',str(HERE/'interleavings.m'),'-framework','Cocoa','-o',str(binary)],check=True)
r=subprocess.run([str(binary)],capture_output=True,text=True,timeout=15);(HERE/'interleavings.log').write_text(r.stdout+r.stderr)
manifest['exit']=r.returncode;manifest['output']=r.stdout
if r.returncode: raise SystemExit(r.stdout+r.stderr)
if '--negative-controls' in sys.argv:
    originals={n:(HERE/n).read_text() for n in ['editor.inc','observer.inc']}
    mutants=[('uncancelled-cleanup','editor.inc','    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(removeHighlightedTerms) object:nil];\n',''),('missing-generation','observer.inc','    ++searchHighlightGeneration;\n','')]
    manifest['negative_controls']={}
    try:
        for name,filename,old,new in mutants:
            for f,body in originals.items(): (HERE/f).write_text(body)
            assert old in originals[filename]
            (HERE/filename).write_text(originals[filename].replace(old,new))
            mutant=binary.with_name(binary.name+'-'+name)
            subprocess.run(['xcrun','clang','-fno-objc-arc','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer',str(HERE/'interleavings.m'),'-framework','Cocoa','-o',str(mutant)],check=True)
            neg=subprocess.run([str(mutant)],capture_output=True,text=True,timeout=15)
            (HERE/(name+'.log')).write_text(neg.stdout+neg.stderr)
            assert neg.returncode!=0, name+' unexpectedly passed'
            manifest['negative_controls'][name]={'exit':neg.returncode,'failure':neg.stderr.strip()}
            print('REJECTED:',name,neg.stderr.strip())
    finally:
        for f,body in originals.items(): (HERE/f).write_text(body)
(HERE/'interleavings.json').write_text(json.dumps(manifest,indent=2)+'\n');print(r.stdout+r.stderr)

