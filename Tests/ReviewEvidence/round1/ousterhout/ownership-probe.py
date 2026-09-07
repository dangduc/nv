#!/usr/bin/env python3
"""Compile actual ownership statements without Cocoa view teardown."""
from pathlib import Path
import re
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[4]
prefs = (repo / 'Sources/Preferences/GlobalPrefs.m').read_text()
editor = (repo / 'Sources/Editor/LinkingEditor.m').read_text()
accessor = re.search(r'\+ \(GlobalPrefs \*\)defaultPrefs \{.*?\n\}', prefs, re.S).group(0)
assignment = re.search(r'prefsController = \[GlobalPrefs defaultPrefs\];', editor).group(0)
release = re.search(r'\[prefsController release\];', editor).group(0)
source = r'''#import <Foundation/Foundation.h>
static BOOL singletonFreed=NO;
@interface GlobalPrefs:NSObject
+ (GlobalPrefs*)defaultPrefs;
@end
@implementation GlobalPrefs
ACCESSOR
- (void)dealloc { singletonFreed=YES; [super dealloc]; }
@end
@interface EditorOwnership:NSObject { GlobalPrefs *prefsController; }
@end
@implementation EditorOwnership
- (id)init { if ((self=[super init])) { ASSIGNMENT } return self; }
- (void)dealloc { RELEASE [super dealloc]; }
@end
int main(void) { NSAutoreleasePool *pool=[NSAutoreleasePool new];
GlobalPrefs *appPrefs=[GlobalPrefs defaultPrefs];
EditorOwnership *editor=[EditorOwnership new];
printf("before editor closes: singleton retain count=%lu\n",(unsigned long)[appPrefs retainCount]);
[editor release];
printf("after editor closes: singleton deallocated=%s; accessor still returns same pointer=%s\n",singletonFreed?"YES":"NO",[GlobalPrefs defaultPrefs]==appPrefs?"YES":"NO");
[pool drain]; return singletonFreed ? 0 : 1; }
'''.replace('ACCESSOR', accessor).replace('ASSIGNMENT', assignment).replace('RELEASE', release)
with tempfile.TemporaryDirectory(prefix='nv-review-ownership-') as tmp:
    tmp = Path(tmp)
    for name, code in [('current', source), ('negative-control', source.replace(release, '').replace('return singletonFreed ? 0 : 1;', 'return singletonFreed ? 1 : 0;'))]:
        print(name + ':', flush=True)
        (tmp / 'probe.m').write_text(code)
        subprocess.run(['xcrun', 'clang', '-fno-objc-arc', '-framework', 'Foundation', str(tmp / 'probe.m'), '-o', str(tmp / 'probe')], check=True)
        subprocess.run([str(tmp / 'probe')], check=True, timeout=10)
