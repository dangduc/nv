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
source=out/'probe-optimized.m';library=out/'probe-optimized.dylib'
source.write_text((here/'support.h').read_text()+prefix+'- (void)nv_runTests {'+(here/'body.m').read_text())
subprocess.run(['xcrun','clang','-arch','x86_64','-O2','-mmacosx-version-min=10.13','-dynamiclib','-undefined','dynamic_lookup','-fno-objc-arc','-Wno-deprecated-declarations',*include_flags(repo),'-include',str(repo/'Config/Notation_Prefix.pch'),'-framework','Cocoa','-framework','Carbon','-framework','WebKit','-o',str(library),str(source)],check=True)
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--after-first',action='store_true')
parser.add_argument('--before-app',type=Path,default=out/'Unoptimized.app')
parser.add_argument('--after-app',type=Path,default=repo/'build/DerivedData/Build/Products/Development/nvALT.app')
args=parser.parse_args()
apps={'before':args.before_app,'after':args.after_app}
tag='optimized-after-first' if args.after_first else 'optimized-before-first'
if args.after_first:apps=dict(reversed(list(apps.items())))
results={}
with open('/Users/duc/dev/nv/build/pr-review/gui.lock','a') as lock:
 fcntl.flock(lock,fcntl.LOCK_EX)
 for mode,original in apps.items():
  with tempfile.TemporaryDirectory(prefix='nv-wrap-r2-mixed-') as temporary:
   root=Path(temporary);app=root/'Mixed Source Review.app';shutil.copytree(original,app,symlinks=True)
   info_path=app/'Contents/Info.plist';info=plistlib.loads(info_path.read_bytes())
   info['CFBundleIdentifier']='org.nvalt.window-tests.'+uuid.uuid4().hex;info_path.write_bytes(plistlib.dumps(info))
   binary=app/'Contents/MacOS'/info['CFBundleExecutable'];digest=hashlib.sha256(binary.read_bytes()).hexdigest()
   assert digest=={'before':'be02dd1fe33a39c74b8961441be55f4f91378d46935bdba99fd610d405c3e09b','after':'55f97d1af69d120f385698b428a616e473be020200d3fe0ebcc6b626253459be'}[mode],digest
   for name in ('Notes','Support','Temp'):(root/name).mkdir()
   output=out/(mode+'-'+tag+'.json')
   env=dict(os.environ,NV_WINDOW_TEST_DIRECTORY=str(root),DYLD_INSERT_LIBRARIES=str(library),TMPDIR=str(root/'Temp')+'/',NV_R2_MODE=mode,NV_R2_OUTPUT=str(output))
   result=subprocess.run([str(binary),'-ShowDockIcon','YES','-StatusBarItem','NO','-QuitWhenClosingMainWindow','NO'],env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=130)
   (out/(mode+'-'+tag+'.log')).write_text(result.stdout);print(mode,result.returncode,result.stdout[-1200:])
   assert result.returncode==0 and 'MIXED SOURCE REVIEW PASSED' in result.stdout
   results[mode]={'sha256':digest,**json.loads(output.read_text())}
for result in results.values():
 assert result['styleCount']==1 and result['styleOffMainCalls']==0
 assert result['styleCalls']>192
(here/('optimized-results-after-first.json' if args.after_first else 'optimized-results-before-first.json')).write_text(json.dumps(results,indent=2)+'\n')
for case in ['many-paragraphs']:
 print(case)
 for mode in apps:
  samples=[x for x in results[mode]['trials']if x['case']==case]
  print(mode,{k:round(statistics.median(x[k]for x in samples),3)for k in ['dispatchMs','cpuMs','resizeTotalMs','resizeMaxMs','glyphOverrideMs','glyphCalls']})
assert {r['finalLines'] for d in results.values() for r in d['trials']}=={1027}
print('PASS: both production glyph implementations enabled; identical source, caret, style, final line count')
