#!/usr/bin/env python3
"""Review evidence: production model/archive with native test AES and UI scaffolding."""
from pathlib import Path
import subprocess
import sys
repo = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(repo / 'Tests'))
from compiler_support import include_flags
out = repo / 'build/BackupReview/round1/contrarian_data'
out.mkdir(parents=True, exist_ok=True)
# Use the production compression and portable PBKDF2 methods unchanged. The only crypto
# substitution is the separately documented native AES provider.
data_source = (repo / 'Sources/Utilities/NSData_transformations.m').read_text()
methods = data_source[data_source.index('@implementation NSData (NVUtilities)'):data_source.index('- (unsigned long)CRC32')]
(out / 'data-methods.m').write_text('#import "NSData_transformations.h"\n#include "pbkdf2.h"\n#include <zlib.h>\n#include <unistd.h>\n' + methods + '\n@end\n')
main = (Path(__file__).parent / 'probe.m').read_text()
(out / 'main.m').write_text(main)
objc_sources = ['Sources/Model/NoteObject.m', 'Sources/Preferences/NotationPrefs.m', 'Sources/Storage/FrozenNotation.m',
    'Sources/Storage/NVBackupArchive.m', 'Sources/Storage/DiskUUIDEntry.m', 'Sources/Model/LabelObject.m',
    'Tests/BackupArchive/native/support.m', 'Tests/BackupArchive/native/aes-provider.m',
    'build/BackupReview/round1/contrarian_data/data-methods.m', 'build/BackupReview/round1/contrarian_data/main.m']
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
