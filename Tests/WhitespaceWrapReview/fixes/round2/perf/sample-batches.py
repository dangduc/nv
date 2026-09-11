#!/usr/bin/env python3
"""Measure mixed-source key events and visible resize work in the frozen app."""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import statistics
import subprocess
import sys
import tempfile
import uuid
import argparse

here=Path(__file__).resolve().parent
repo=here.parents[4]
out=repo/'build/WhitespaceWrapReview/fixes/round2/perf'
out.mkdir(parents=True,exist_ok=True)
sys.path.insert(0,str(repo/'Tests'))
from compiler_support import include_flags
prefix=(repo/'Tests/MultipleWindowsTests.m').read_text().split('- (void)nv_runTests {')[0]
prefix=prefix.replace('[[self window] makeKeyAndOrderFront:self];','[NSApp activateIgnoringOtherApps:YES]; [[self window] makeKeyAndOrderFront:self];')
source=out/'probe-batches.m';library=out/'probe-batches.dylib'
support=(here/'support.h').read_text().replace('static uint64_t GlyphTicks;', 'static uint64_t GlyphTicks; static NSUInteger SingleCalls,ChangedCalls,MaxRange,GlyphUnits;')
support=support.replace('    GlyphCalls++;','    GlyphCalls++; if(range.length==1)SingleCalls++; MaxRange=MAX(MaxRange,range.length); GlyphUnits+=range.length;')
support=support.replace('    GlyphTicks+=mach_absolute_time()-start;','    if(result)ChangedCalls++; GlyphTicks+=mach_absolute_time()-start;')
body=(here/'body.m').read_text().replace('trial<3','trial<1')
body=body.replace('uint64_t glyphStart=GlyphTicks;', 'SingleCalls=ChangedCalls=MaxRange=GlyphUnits=0; uint64_t glyphStart=GlyphTicks;')
body=body.replace('@"glyphCalls":@(GlyphCalls-glyphCallsStart)', '@"singleGlyphCalls":@(SingleCalls),@"changedCalls":@(ChangedCalls),@"maxRange":@(MaxRange),@"glyphUnits":@(GlyphUnits),@"glyphCalls":@(GlyphCalls-glyphCallsStart)')
source.write_text(support+prefix+'- (void)nv_runTests {'+body)
subprocess.run(['xcrun','clang','-arch','x86_64','-O2','-mmacosx-version-min=10.13','-dynamiclib','-undefined','dynamic_lookup','-fno-objc-arc','-Wno-deprecated-declarations',*include_flags(repo),'-include',str(repo/'Config/Notation_Prefix.pch'),'-framework','Cocoa','-framework','Carbon','-framework','WebKit','-o',str(library),str(source)],check=True)
apps={'glyph-on':out/'Unoptimized.app'}
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--app',type=Path,default=out/'Unoptimized.app')
args=parser.parse_args()
tag='batch-sample'
apps={'glyph-on':args.app}
results={}
with open('/Users/duc/dev/nv/build/pr-review/gui.lock','a') as lock:
 fcntl.flock(lock,fcntl.LOCK_EX)
 for mode,original in apps.items():
  with tempfile.TemporaryDirectory(prefix='nv-wrap-r2-mixed-') as temporary:
   root=Path(temporary);app=root/'Mixed Source Review.app';shutil.copytree(original,app,symlinks=True)
   info_path=app/'Contents/Info.plist';info=plistlib.loads(info_path.read_bytes())
   info['CFBundleIdentifier']='org.nvalt.window-tests.'+uuid.uuid4().hex;info_path.write_bytes(plistlib.dumps(info))
   binary=app/'Contents/MacOS'/info['CFBundleExecutable'];digest=hashlib.sha256(binary.read_bytes()).hexdigest()
   assert digest=='be02dd1fe33a39c74b8961441be55f4f91378d46935bdba99fd610d405c3e09b',digest
   for name in ('Notes','Support','Temp'):(root/name).mkdir()
   output=out/(mode+'-'+tag+'.json')
   env=dict(os.environ,NV_WINDOW_TEST_DIRECTORY=str(root),DYLD_INSERT_LIBRARIES=str(library),TMPDIR=str(root/'Temp')+'/',NV_R2_MODE=mode,NV_R2_OUTPUT=str(output))
   result=subprocess.run([str(binary),'-ShowDockIcon','YES','-StatusBarItem','NO','-QuitWhenClosingMainWindow','NO'],env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=130)
   (out/(mode+'-'+tag+'.log')).write_text(result.stdout);print(mode,result.returncode,result.stdout[-1200:])
   assert result.returncode==0 and 'MIXED SOURCE REVIEW PASSED' in result.stdout
   results[mode]={'sha256':digest,**json.loads(output.read_text())}
for result in results.values():
 assert result['styleCount']==1 and result['styleOffMainCalls']==0
 assert result['styleCalls']>64
(here/('results-batch-sample.json')).write_text(json.dumps(results,indent=2)+'\n')
for case in ['many-paragraphs']:
 print(case)
 for mode in apps:
  samples=[x for x in results[mode]['trials']if x['case']==case]
  print(mode,{k:round(statistics.median(x[k]for x in samples),3)for k in ['dispatchMs','cpuMs','resizeTotalMs','resizeMaxMs','glyphOverrideMs','glyphCalls']})
print('PASS: same frozen app, identical character-wrap style, isolated glyph callback control')
