#!/usr/bin/env python3
"""Compile production toolbar methods for 10.13; prove the guard matters."""
import hashlib
import json
from pathlib import Path
import subprocess

repo = Path(__file__).resolve().parents[4]
out = repo / 'build/TitlebarReview/round1/torvalds'
out.mkdir(parents=True, exist_ok=True)
source = (repo / 'Sources/Browser/AppController_BrowserUI.m').read_text()
start = source.index('- (void)setDualFieldInToolbar {')
method = source[start:source.index('\n}', start) + 2]
prefix = '''#import <Cocoa/Cocoa.h>
@interface ToolbarFixture : NSObject <NSSearchFieldDelegate, NSToolbarDelegate> {
    NSSearchField *field;
    NSWindow *window;
    NSToolbar *toolbar;
    NSToolbarItem *dualFieldItem;
}
@end
@implementation ToolbarFixture
'''
variants = {
    'production': method,
    'negative-unguarded': method.replace('if (@available(macOS 11.0, *)) {', 'if (YES) {'),
}
records = {}
for name, body in variants.items():
    path = out / (name + '.m')
    path.write_text(prefix + body + '\n@end\n')
    command = ['xcrun', 'clang', '-arch', 'x86_64', '-mmacosx-version-min=10.13',
               '-fsyntax-only', '-fno-objc-arc', '-Werror=unguarded-availability',
               '-Werror=unguarded-availability-new', '-Wno-deprecated-declarations', str(path)]
    result = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (out / (name + '.compile.log')).write_text(result.stdout)
    records[name] = {'exit_code': result.returncode, 'command': command,
                     'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
assert records['production']['exit_code'] == 0, 'Production uses an unavailable API without a guard.'
assert records['negative-unguarded']['exit_code'] != 0, 'Negative control must catch the absent guard.'
records['production_method_sha256'] = hashlib.sha256(method.encode()).hexdigest()
records['limitation'] = 'SDK availability compilation does not execute on macOS 10.13.'
(out / 'availability.json').write_text(json.dumps(records, indent=2) + '\n')
print('PASS: production toolbar compiles for macOS 10.13; removing the macOS 11 guard fails compilation.')
