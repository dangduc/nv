#!/usr/bin/env python3
"""Run unchanged window suite against an app; optional baseline-only cleanup suppression."""
import argparse, fcntl, json, os, plistlib, shutil, subprocess, sys, tempfile, uuid
from pathlib import Path
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
sys.path.insert(0, str(ROOT/'Tests'))
from compiler_support import include_flags
p=argparse.ArgumentParser(); p.add_argument('--app',type=Path,required=True); p.add_argument('--label',required=True); p.add_argument('--suppress-early-cleanup',action='store_true'); a=p.parse_args()
lock_path=Path(subprocess.check_output(['git','rev-parse','--git-common-dir'],cwd=ROOT,text=True).strip()).resolve().parent/'build/pr-review/gui.lock'
lock_path.parent.mkdir(parents=True,exist_ok=True)
lock=lock_path.open('w'); fcntl.flock(lock,fcntl.LOCK_EX)
source=(ROOT/'Tests/MultipleWindowsTests.m').read_text()
if a.suppress_early_cleanup:
    source=source.replace('@implementation AppController (NVWindowTests)', '''@implementation AppController (NVWindowTests)
- (void)nv_skipEarlyHighlightCleanup:(NSNotification *)notification {
    NSTextStorage *storage = [notification object];
    if (storage != [textView textStorage] || !([storage editedMask] & NSTextStorageEditedCharacters)) return;
    ++searchHighlightGeneration;
}
''')
    source=source.replace('TestDirectory = [[NSString stringWithUTF8String:directory] copy];','TestDirectory = [[NSString stringWithUTF8String:directory] copy];\n    Swap(self, @selector(searchSourceStorageWillProcessEditing:), @selector(nv_skipEarlyHighlightCleanup:));')
harness=ROOT/'build'/('SourceBackspaceReview-kingsbury-'+a.label+'-harness.m')
harness.write_text(source)
result={'app':str(a.app),'baseline_cleanup_suppressed':a.suppress_early_cleanup,'phases':{}}
with tempfile.TemporaryDirectory(prefix='nvalt-kingsbury-r1-') as tmp:
    tmp=Path(tmp); app=tmp/'Review.app'; shutil.copytree(a.app,app,symlinks=True)
    ip=app/'Contents/Info.plist'; info=plistlib.loads(ip.read_bytes()); info['CFBundleIdentifier']='org.nvalt.kingsbury.'+uuid.uuid4().hex; ip.write_bytes(plistlib.dumps(info))
    for n in ['Notes','Support','Temp']: (tmp/n).mkdir()
    lib=tmp/'Review.dylib'
    subprocess.run(['xcrun','clang','-arch','x86_64','-mmacosx-version-min=10.13','-dynamiclib','-undefined','dynamic_lookup','-fno-objc-arc','-Wno-deprecated-declarations',*include_flags(ROOT),'-include',str(ROOT/'Config/Notation_Prefix.pch'),'-framework','Cocoa','-framework','Carbon','-o',str(lib),str(harness)],check=True)
    env=dict(os.environ,NV_WINDOW_TEST_DIRECTORY=str(tmp),DYLD_INSERT_LIBRARIES=str(lib),TMPDIR=str(tmp/'Temp')+'/')
    binary=app/'Contents/MacOS'/info['CFBundleExecutable']
    args=[str(binary),'-ShowDockIcon','YES','-StatusBarItem','NO','-QuitWhenClosingMainWindow','NO','-SUEnableAutomaticChecks','NO']
    for phase in ['main','relaunch']:
        if phase=='relaunch': env['NV_WINDOW_TEST_RELAUNCH']='1'
        r=subprocess.run(args,env=env,timeout=90,capture_output=True,text=True)
        out=r.stdout+r.stderr;(HERE/(a.label+'-'+phase+'.log')).write_text(out)
        checks=out.count('PASS: '); result['phases'][phase]={'exit':r.returncode,'checks':checks,'last_lines':out.splitlines()[-3:]}
        print(a.label,phase,r.returncode,checks,flush=True)
        if r.returncode: break
(HERE/(a.label+'-results.json')).write_text(json.dumps(result,indent=2)+'\n')
