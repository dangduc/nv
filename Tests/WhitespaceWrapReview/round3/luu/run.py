#!/usr/bin/env python3
"""Final short-note typing benchmark plus a separate scoped allocation sample."""
import argparse
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

here=Path(__file__).resolve().parent;repo=here.parents[3]
out=repo/'build/WhitespaceWrapReview/round3/luu';out.mkdir(parents=True,exist_ok=True)
sys.path.insert(0,str(repo/'Tests'))
from compiler_support import include_flags
parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--allocations',action='store_true');args=parser.parse_args()
tag='allocations' if args.allocations else 'timing'
prefix=(repo/'Tests/MultipleWindowsTests.m').read_text().split('- (void)nv_runTests {')[0]
prefix=prefix.replace('[[self window] makeKeyAndOrderFront:self];','[NSApp activateIgnoringOtherApps:YES]; [[self window] makeKeyAndOrderFront:self];')
support=(here/'support.h').read_text().replace('/*INTERPOSE*/',(here/'allocation.h').read_text() if args.allocations else '')
source=out/(tag+'.m');library=out/(tag+'.dylib')
source.write_text(support+prefix+'- (void)nv_runTests {'+(here/'body.m').read_text())
subprocess.run(['xcrun','clang','-arch','x86_64','-O2','-mmacosx-version-min=10.13','-dynamiclib','-undefined','dynamic_lookup','-fno-objc-arc','-Wno-deprecated-declarations',*include_flags(repo),'-include',str(repo/'Config/Notation_Prefix.pch'),'-framework','Cocoa','-framework','Carbon','-framework','WebKit','-o',str(library),str(source)],check=True)
apps={'before':repo/'build/WhitespaceWrapReview/fixes/round2/perf/Unoptimized.app','final':repo/'build/DerivedData/Build/Products/Development/nvALT.app'}
expected={'before':'be02dd1fe33a39c74b8961441be55f4f91378d46935bdba99fd610d405c3e09b','final':'55f97d1af69d120f385698b428a616e473be020200d3fe0ebcc6b626253459be'}
results={}
with open('/Users/duc/dev/nv/build/pr-review/gui.lock','a')as lock:
 fcntl.flock(lock,fcntl.LOCK_EX)
 for label,original in apps.items():
  with tempfile.TemporaryDirectory(prefix='nv-final-short-')as temporary:
   root=Path(temporary);app=root/'Short Note Review.app';shutil.copytree(original,app,symlinks=True)
   info_path=app/'Contents/Info.plist';info=plistlib.loads(info_path.read_bytes());info['CFBundleIdentifier']='org.nvalt.window-tests.'+uuid.uuid4().hex;info_path.write_bytes(plistlib.dumps(info))
   binary=app/'Contents/MacOS'/info['CFBundleExecutable'];digest=hashlib.sha256(binary.read_bytes()).hexdigest();assert digest==expected[label],digest
   for name in ('Notes','Support','Temp'):(root/name).mkdir()
   output=out/(label+'-'+tag+'.json')
   env=dict(os.environ,NV_WINDOW_TEST_DIRECTORY=str(root),DYLD_INSERT_LIBRARIES=str(library),TMPDIR=str(root/'Temp')+'/',NV_R3_SAMPLE='1'if args.allocations else '0',NV_R3_OUTPUT=str(output))
   run=subprocess.run([str(binary),'-ShowDockIcon','YES','-StatusBarItem','NO','-QuitWhenClosingMainWindow','NO'],env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=130)
   (out/(label+'-'+tag+'.log')).write_text(run.stdout);print(label,tag,run.returncode,run.stdout[-1000:])
   assert run.returncode==0 and 'SHORT NOTE REVIEW PASSED' in run.stdout
   results[label]={'sha256':digest,**json.loads(output.read_text())}
if args.allocations:
 before=results['before']['trials'][0];after=results['final']['trials'][0]
 assert before['glyphCalls']>0 and after['glyphCalls']>0
 assert before['mallocs']>after['mallocs']
 assert before['changedSmall']>0 and after['changedSmall']>0
(here/(tag+'-results.json')).write_text(json.dumps(results,indent=2)+'\n')
for font in ['Menlo-Regular','Helvetica']:
 for label in apps:
  trials=[x for x in results[label]['trials']if x['font']==font]
  if trials:print(font,label,{k:round(statistics.median(x[k]for x in trials),3)for k in ['dispatchMs','cpuMs','glyphCalls','changedSmall','changedLarge','mallocs','mallocBytes']})
print('PASS: exact binary identities,20notes,empty search,real key events,source/model/caret')
