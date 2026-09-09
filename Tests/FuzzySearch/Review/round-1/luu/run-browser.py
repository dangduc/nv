#!/usr/bin/env python3
"""Measure actual browser publication and coordinator capture on native arm64."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
ROOT = Path(__file__).resolve().parents[5]
HERE = Path(__file__).resolve().parent
OUT = ROOT / 'build/FuzzySearchReview/round-1/luu/browser'
OUT.mkdir(parents=True, exist_ok=True)
sys.path.insert(0, str(ROOT/'Tests'))
from compiler_support import include_flags

def extract(path, prefixes, name):
    text = (ROOT/path).read_text()
    methods = []
    for prefix in prefixes:
        start = text.index(prefix)
        methods.append(text[start:text.index('\n}',start)+2])
    (OUT/name).write_text('\n'.join(methods))

extract('Sources/Model/FastListDataSource.m', ['- (void)fillArrayFromArray:', '- (NSUInteger)count', '- (NSUInteger)indexOfObjectIdenticalTo:'], 'datasource.inc')
extract('Sources/Application/NVApplicationController.m', ['- (NVSearchNoteSnapshot *)searchSnapshotForNote:', '- (void)searchableNoteDidChange:'], 'capture.inc')
production = ['Sources/Search/NVFZF.c', 'ThirdParty/fzf-native/fzf.c', 'ThirdParty/fzf-native/utf8proc-2.10.0/utf8proc.c', 'Sources/Search/NVSearchQuery.m', 'Sources/Search/NVSearchCorpus.m', 'Sources/Search/NVSearchService.m', 'Sources/Browser/NVBrowserSession.m']
tracked = production + ['Sources/Application/NVApplicationController.m', 'Sources/Model/FastListDataSource.m']
(HERE/'browser-source-record.json').write_text(json.dumps({'head': subprocess.check_output(['git','rev-parse','HEAD'], cwd=ROOT,text=True).strip(),'source_sha256': {p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in tracked}},indent=2)+'\n')
flags = ['-arch','arm64','-O2','-g','-DUTF8PROC_STATIC','-I'+str(OUT),'-I'+str(ROOT/'ThirdParty/fzf-native'),*include_flags(ROOT)]
objects=[]
for i, path in enumerate([*(ROOT/p for p in production),HERE/'browser-probe.m']):
    obj=OUT/f'{i}.o'
    language=['-fblocks','-fno-objc-arc','-Wno-deprecated-declarations','-Wno-incomplete-implementation','-Wno-protocol','-include',str(ROOT/'Config/Notation_Prefix.pch')] if path.suffix=='.m' else ['-std=c11']
    subprocess.run(['xcrun','clang',*flags,*language,'-c',str(path),'-o',str(obj)],check=True)
    objects.append(str(obj))
exe=OUT/'browser'
subprocess.run(['xcrun','clang',*flags,*objects,'-framework','Cocoa','-framework','Carbon','-o',str(exe)],check=True)
result=subprocess.run([str(exe)],check=True,capture_output=True,text=True,timeout=45)
print(result.stdout,end='')
print(result.stderr,end='',file=sys.stderr)
(HERE/'browser.csv').write_text(result.stdout)
