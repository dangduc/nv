#!/usr/bin/env python3
"""Measure real nvALT reflow and short-note typing before and after character wrapping."""
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

here=Path(__file__).resolve().parent
repo=here.parents[4]
out=repo/'build/WhitespaceWrapReview/fixes/round1/perf'
out.mkdir(parents=True,exist_ok=True)
sys.path.insert(0,str(repo/'Tests'))
from compiler_support import include_flags
prefix=(repo/'Tests/MultipleWindowsTests.m').read_text().split('- (void)nv_runTests {')[0]
prefix=prefix.replace('[[self window] makeKeyAndOrderFront:self];','[NSApp activateIgnoringOtherApps:YES]; [[self window] makeKeyAndOrderFront:self];')
source=out/'probe.m'
source.write_text((here/'support.h').read_text()+prefix+'- (void)nv_runTests {'+(here/'body.m').read_text())
library=out/'probe.dylib'
subprocess.run(['xcrun','clang','-arch','x86_64','-O2','-mmacosx-version-min=10.13','-dynamiclib','-undefined','dynamic_lookup','-fno-objc-arc','-Wno-deprecated-declarations',*include_flags(repo),'-include',str(repo/'Config/Notation_Prefix.pch'),'-framework','Cocoa','-framework','Carbon','-framework','WebKit','-o',str(library),str(source)],check=True)
results={}
with tempfile.TemporaryDirectory(prefix='nv-wrap-perf-') as temporary:
 root=Path(temporary)
 old=root/'Archive';old.mkdir()
 subprocess.run(['ditto','-x','-k',str(repo/'build/WhitespaceWrapping/nvALT-Space-Wrap.zip'),str(old)],check=True)
 old_apps=list(old.rglob('nvALT.app'));assert len(old_apps)==1,old_apps
 apps={'native':Path('/Users/duc/dev/nv/build/TypingPerformanceWorktree/build/DerivedData/Build/Products/Development/nvALT.app'),
       'before':old_apps[0], 'fixed':repo/'build/DerivedData/Build/Products/Development/nvALT.app'}
 with open('/Users/duc/dev/nv/build/pr-review/gui.lock','a') as lock:
  fcntl.flock(lock,fcntl.LOCK_EX)
  for mode,original in apps.items():
   task=root/mode;task.mkdir()
   app=task/'Performance Review.app';shutil.copytree(original,app,symlinks=True)
   info_path=app/'Contents/Info.plist';info=plistlib.loads(info_path.read_bytes())
   info['CFBundleIdentifier']='org.nvalt.window-tests.'+uuid.uuid4().hex
   info_path.write_bytes(plistlib.dumps(info))
   binary=app/'Contents/MacOS'/info['CFBundleExecutable']
   digest=hashlib.sha256(binary.read_bytes()).hexdigest()
   if mode=='before':assert digest=='6682e85cff4069c18b65ef9989830de2b72c3513240302a197395551d53d7d0c',digest
   for name in ('Notes','Support','Temp'):(task/name).mkdir()
   output=out/(mode+'.json')
   env=dict(os.environ,NV_WINDOW_TEST_DIRECTORY=str(task),DYLD_INSERT_LIBRARIES=str(library),TMPDIR=str(task/'Temp')+'/',NV_WRAP_PERF_MODE=mode,NV_WRAP_PERF_OUTPUT=str(output))
   r=subprocess.run([str(binary),'-ShowDockIcon','YES','-StatusBarItem','NO','-QuitWhenClosingMainWindow','NO'],env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=100)
   (out/(mode+'.log')).write_text(r.stdout)
   print(mode,'exit',r.returncode,r.stdout[-1400:])
   assert r.returncode==0 and 'WRAP PERF PASSED' in r.stdout
   results[mode]={'sha256':digest,**json.loads(output.read_text())}
(here/'results.json').write_text(json.dumps(results,indent=2)+'\n')
print('spaces | native resize ms | before resize ms | fixed resize ms')
for length in [4096,8192,16384,32768]:
 print(length,*[round(statistics.median(x['ms']for x in results[m]['reflows']if x['length']==length),3)for m in apps])
print('short note | native | before | fixed')
for metric in ['dispatchMs','cpuMs']:
 print(metric,*[round(statistics.median(x[metric]for x in results[m]['typing']),3)for m in apps])
