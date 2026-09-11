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
repo=here.parents[3]
out=repo/'build/WhitespaceWrapReview/round2/luu'
out.mkdir(parents=True,exist_ok=True)
sys.path.insert(0,str(repo/'Tests'))
from compiler_support import include_flags
prefix=(repo/'Tests/MultipleWindowsTests.m').read_text().split('- (void)nv_runTests {')[0]
prefix=prefix.replace('[[self window] makeKeyAndOrderFront:self];','[NSApp activateIgnoringOtherApps:YES]; [[self window] makeKeyAndOrderFront:self];')
source=out/'probe.m';library=out/'probe.dylib'
source.write_text((here/'support.h').read_text()+prefix+'- (void)nv_runTests {'+(here/'body.m').read_text())
subprocess.run(['xcrun','clang','-arch','x86_64','-O2','-mmacosx-version-min=10.13','-dynamiclib','-undefined','dynamic_lookup','-fno-objc-arc','-Wno-deprecated-declarations',*include_flags(repo),'-include',str(repo/'Config/Notation_Prefix.pch'),'-framework','Cocoa','-framework','Carbon','-framework','WebKit','-o',str(library),str(source)],check=True)
apps={'native':Path('/Users/duc/dev/nv/build/TypingPerformanceWorktree/build/DerivedData/Build/Products/Development/nvALT.app'),
      'candidate':repo/'build/DerivedData/Build/Products/Development/nvALT.app'}
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--candidate-first',action='store_true')
args=parser.parse_args()
tag='candidate-first' if args.candidate_first else 'native-first'
if args.candidate_first:apps=dict(reversed(list(apps.items())))
results={}
with open('/Users/duc/dev/nv/build/pr-review/gui.lock','a') as lock:
 fcntl.flock(lock,fcntl.LOCK_EX)
 for mode,original in apps.items():
  with tempfile.TemporaryDirectory(prefix='nv-wrap-r2-mixed-') as temporary:
   root=Path(temporary);app=root/'Mixed Source Review.app';shutil.copytree(original,app,symlinks=True)
   info_path=app/'Contents/Info.plist';info=plistlib.loads(info_path.read_bytes())
   info['CFBundleIdentifier']='org.nvalt.window-tests.'+uuid.uuid4().hex;info_path.write_bytes(plistlib.dumps(info))
   binary=app/'Contents/MacOS'/info['CFBundleExecutable'];digest=hashlib.sha256(binary.read_bytes()).hexdigest()
   if mode=='candidate':assert digest=='be02dd1fe33a39c74b8961441be55f4f91378d46935bdba99fd610d405c3e09b',digest
   for name in ('Notes','Support','Temp'):(root/name).mkdir()
   output=out/(mode+'-'+tag+'.json')
   env=dict(os.environ,NV_WINDOW_TEST_DIRECTORY=str(root),DYLD_INSERT_LIBRARIES=str(library),TMPDIR=str(root/'Temp')+'/',NV_R2_MODE=mode,NV_R2_OUTPUT=str(output))
   result=subprocess.run([str(binary),'-ShowDockIcon','YES','-StatusBarItem','NO','-QuitWhenClosingMainWindow','NO'],env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=130)
   (out/(mode+'-'+tag+'.log')).write_text(result.stdout);print(mode,result.returncode,result.stdout[-1200:])
   assert result.returncode==0 and 'MIXED SOURCE REVIEW PASSED' in result.stdout
   results[mode]={'sha256':digest,**json.loads(output.read_text())}
assert results['candidate']['styleCount']==1
assert results['candidate']['styleCalls']>384
assert results['candidate']['styleOffMainCalls']==0
(here/('results-candidate-first.json' if args.candidate_first else 'results.json')).write_text(json.dumps(results,indent=2)+'\n')
for case in ['single-paragraph','many-paragraphs']:
 print(case)
 for mode in apps:
  samples=[x for x in results[mode]['trials']if x['case']==case]
  print(mode,{k:round(statistics.median(x[k]for x in samples),3)for k in ['dispatchMs','cpuMs','resizeTotalMs','resizeMaxMs']})
print('PASS: real native keys, visible resize requests, frozen binary identity, shared style identity')
