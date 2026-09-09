#!/usr/bin/env python3
"""Native offline archive checks; no app/journal/UI startup and no shipping Intel OpenSSL."""
from pathlib import Path
import subprocess
import sys
repo = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(repo / 'Tests'))
from compiler_support import include_flags
out = repo / 'build/BackupArchive/native'
out.mkdir(parents=True, exist_ok=True)
# Use the production compression and portable PBKDF2 methods unchanged. The only crypto
# substitution is the separately documented native AES provider.
data_source = (repo / 'Sources/Utilities/NSData_transformations.m').read_text()
methods = data_source[data_source.index('@implementation NSData (NVUtilities)'):data_source.index('- (unsigned long)CRC32')]
(out / 'data-methods.m').write_text('#import "NSData_transformations.h"\n#include "pbkdf2.h"\n#include <zlib.h>\n#include <unistd.h>\n' + methods + '\n@end\n')
checks = (repo / 'Tests/BackupArchive/checks.inc').read_text().split('- (void)nv_runTests {')[0]
main = '''#import <Cocoa/Cocoa.h>
#import "NoteObject.h"
#import "NotationPrefs.h"
#import "FrozenNotation.h"
#import "NVBackupArchive.h"
#include <sys/resource.h>
static NSUInteger Checks;
static void Check(BOOL result, NSString *message) { if (!result) { NSLog(@"FAIL: %@", message); exit(1); } Checks++; }
@interface ArchiveChecks : NSObject @end
@implementation ArchiveChecks
''' + checks + '\n@end\n' + (repo / 'Tests/BackupArchive/native/benchmark.inc').read_text() + '''
int main(void) { @autoreleasepool {
    ArchiveChecks *checks = [[[ArchiveChecks alloc] init] autorelease];
    for (int format=0; format<=1; format++) for (int encrypted=0; encrypted<=1; encrypted++)
        [checks nv_backupRoundTrip:format encrypted:encrypted];
    NSError *error = nil;
    Check(![NVBackupArchive restoredArchiveFromData:[@"damaged" dataUsingEncoding:NSUTF8StringEncoding] error:&error] && error, @"corrupt archive rejected");
    NotationPrefs *prefs = [[[NotationPrefs alloc] init] autorelease];
    NSDictionary *empty = [NVBackupArchive restoredArchiveFromData:[FrozenNotation frozenDataWithExistingNotes:[NSMutableArray array] prefs:prefs] error:&error];
    Check(empty && [[empty objectForKey:@"noteCount"] unsignedIntegerValue] == 0, @"empty archive restored");
    Benchmark(1000); Benchmark(10000);
    NSLog(@"NATIVE OFFLINE ARCHIVE PASS: %lu checks (CommonCrypto test provider; no application lifecycle)", (unsigned long)Checks);
    return 0;
}}
'''
(out / 'main.m').write_text(main)
objc_sources = ['Sources/Model/NoteObject.m', 'Sources/Preferences/NotationPrefs.m', 'Sources/Storage/FrozenNotation.m',
    'Sources/Storage/NVBackupArchive.m', 'Sources/Storage/DiskUUIDEntry.m', 'Sources/Model/LabelObject.m',
    'Tests/BackupArchive/native/support.m', 'Tests/BackupArchive/native/aes-provider.m',
    'build/BackupArchive/native/data-methods.m', 'build/BackupArchive/native/main.m']
c_sources = ['Sources/Utilities/BufferUtils.c', 'ThirdParty/Crypto/pbkdf2.c', 'ThirdParty/Crypto/hmacsha1.c']
objects = []
for index, source in enumerate(objc_sources + c_sources):
    obj = out / ('part-%d.o' % index)
    command = ['xcrun', 'clang', '-c', '-arch', 'arm64', '-mmacosx-version-min=11.0', '-O1', '-Wno-deprecated-declarations', '-Wno-incomplete-implementation', *include_flags(repo)]
    if source.endswith('.m') or source.endswith('BufferUtils.c'): command += ['-x', 'objective-c'] + ['-fno-objc-arc', '-include', str(repo / 'Config/Notation_Prefix.pch')]
    subprocess.run([*command, str(repo / source), '-o', str(obj)], check=True)
    objects.append(str(obj))
binary = out / 'archive-checks'
subprocess.run(['xcrun', 'clang', '-arch', 'arm64', *objects, '-framework', 'Cocoa', '-framework', 'Carbon', '-framework', 'Security', '-lz', '-o', str(binary)], check=True)
subprocess.run([str(binary)], check=True, timeout=90)
