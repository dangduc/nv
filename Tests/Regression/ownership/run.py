#!/usr/bin/env python3
"""Exercise production editor teardown with native Foundation lifetime sentinels."""
from pathlib import Path
import re
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[3]
editor = (repo / 'Sources/Editor/LinkingEditor.m').read_text()
prefs = (repo / 'Sources/Preferences/GlobalPrefs.m').read_text()
dealloc = re.search(r'^- \(void\)dealloc \{.*?^\}', editor, re.S | re.M).group(0)
accessor = re.search(r'^\+ \(GlobalPrefs \*\)defaultPrefs \{.*?^\}', prefs, re.S | re.M).group(0)
assignment = re.search(r'prefsController = \[GlobalPrefs defaultPrefs\];', editor).group(0)

borrowed = ['prefsController', 'controlField', 'notesTableView', 'beforeString', 'afterString']
for name in borrowed:
    assert not re.search(r'\[' + name + r'\s+(?:release|autorelease)\]', dealloc), name + ' must remain borrowed'
for name in ['textFinder', 'lastImportedFindString', 'stringDuringFind', 'noteDuringFind']:
    assert '[' + name + ' release]' in dealloc, name + ' must release its owned reference'
print('PASS: borrowed and owned reference guards', flush=True)

source = r'''
#import <Foundation/Foundation.h>
#define IsLionOrLater YES
static NSUInteger borrowedDestroyed, ownedDestroyed, singletonDestroyed;
@interface BorrowedSentinel : NSObject @end
@implementation BorrowedSentinel
- (void)dealloc { borrowedDestroyed++; [super dealloc]; }
@end
@interface OwnedSentinel : NSObject @end
@implementation OwnedSentinel
- (void)dealloc { ownedDestroyed++; [super dealloc]; }
@end
@interface GlobalPrefs : NSObject
+ (GlobalPrefs *)defaultPrefs;
@end
@implementation GlobalPrefs
ACCESSOR
- (void)dealloc { singletonDestroyed++; [super dealloc]; }
@end
@interface EditorOwnership : NSObject {
    id textFinder, controlField, notesTableView;
    GlobalPrefs *prefsController;
    id activeParagraphPastCursor, activeParagraph, activeParagraphBeforeCursor;
    id beforeString, afterString, lastImportedFindString, stringDuringFind, noteDuringFind;
}
- (id)initWithBorrowedObjects:(NSArray *)objects;
- (void)unbind:(NSString *)binding;
@end
@implementation EditorOwnership
- (id)initWithBorrowedObjects:(NSArray *)objects {
    if ((self = [super init])) {
        ASSIGNMENT
        controlField = [objects objectAtIndex:0];
        notesTableView = [objects objectAtIndex:1];
        beforeString = [objects objectAtIndex:2];
        afterString = [objects objectAtIndex:3];
        textFinder = [OwnedSentinel new];
        lastImportedFindString = [OwnedSentinel new];
        stringDuringFind = [OwnedSentinel new];
        noteDuringFind = [OwnedSentinel new];
    }
    return self;
}
- (void)unbind:(NSString *)binding { /* Cocoa bindings are outside this test. */ }
DEALLOC
@end
int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    GlobalPrefs *applicationPreferences = [GlobalPrefs defaultPrefs];
    NSMutableArray *owners = [NSMutableArray new];
    for (NSUInteger i = 0; i < 4; i++) {
        id object = [BorrowedSentinel new];
        [owners addObject:object]; [object release];
    }
    EditorOwnership *editor = [[EditorOwnership alloc] initWithBorrowedObjects:owners];
    [editor release];
    printf("after editor closes: borrowed=%lu singleton=%lu owned=%lu\n",
        (unsigned long)borrowedDestroyed, (unsigned long)singletonDestroyed, (unsigned long)ownedDestroyed);
    if (borrowedDestroyed || singletonDestroyed || ownedDestroyed != 4) return 1;
    if ([GlobalPrefs defaultPrefs] != applicationPreferences) return 2;
    [owners release];
    if (borrowedDestroyed != 4) return 3;
    [pool drain]; return 0;
}
'''.replace('ACCESSOR', accessor).replace('ASSIGNMENT', assignment)

with tempfile.TemporaryDirectory(prefix='nv-editor-ownership-') as directory:
    directory = Path(directory)
    cases = [('production', dealloc, 0)]
    cases.extend((name + '-release-mutant', dealloc.replace('[super dealloc];', '[' + name + ' release];\n    [super dealloc];'), 1) for name in borrowed)
    for name, teardown, expected in cases:
        path = directory / 'test.m'
        path.write_text(source.replace('DEALLOC', teardown))
        executable = directory / 'test'
        subprocess.run(['xcrun', 'clang', '-fno-objc-arc', '-framework', 'Foundation', str(path), '-o', str(executable)], check=True)
        result = subprocess.run([str(executable)], capture_output=True, text=True, timeout=10)
        assert result.returncode == expected, name + ': ' + result.stdout + result.stderr
        print('PASS: ' + name + ': ' + result.stdout.strip(), flush=True)
