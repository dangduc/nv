#!/usr/bin/env python3
"""Compile exact production method slices in bounded Foundation test hosts."""
from pathlib import Path
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
model = (ROOT / 'Sources/Model/NoteObject.m').read_text()
manager = (ROOT / 'Sources/ImportExport/EncodingsManager.m').read_text()

def between(text, first, last):
    return text[text.index(first):text.index(last, text.index(first))]

slices = {
    'BOM': between(model, 'static NSUInteger NVSourceBOMLength(', '@implementation NoteObject'),
    'DECODE': between(model, '+ (NSString*)sourceStringFromData:', '- (NSString*)sourceMetadataUUID'),
    'BYTES': between(model, '- (void)rememberSourceBaselineData:(NSData*)data encoding:(NSStringEncoding)encoding {', '- (BOOL)sourceConversionPending'),
    'PROVENANCE': between(model, '- (void)markAsSourceConflictCopyOfNote:', '- (BOOL)preservePendingSourceFileChanges'),
    'ARCHIVE_READ': between(model, '\t\t\tfileEncoding = [decoder decodeInt32ForKey:', '\n\t\t\tNSUInteger decodedUUIDByteCount'),
    'ARCHIVE_WRITE': between(model, '\t\t[coder encodeInt32:fileEncoding', '\n\t\t[coder encodeBytes:(const uint8_t *)&uniqueNoteIDBytes'),
    'REQUESTS': between(manager, '- (void)offerUTF8ConversionForNote:', '- (BOOL)checkUnicode'),
}
slices['REQUESTS'] = slices['REQUESTS'].replace('NoteObject', 'RequestNote').replace('NotationController', 'RequestLibrary').replace('NVApplicationController', 'ReviewCoordinator').replace('NSAlert', 'ReviewAlert').replace('NSApp', 'ReviewApp')
# Avoid replacing Cocoa's constant names along with its class name.
slices['REQUESTS'] = slices['REQUESTS'].replace('ReviewAlertFirstButtonReturn', 'NSAlertFirstButtonReturn')
template = (HERE / 'probe.m').read_text()
for key, value in slices.items():
    template = template.replace('/* ' + key + ' */', value)
assert '/* DECODE */' not in template

with tempfile.TemporaryDirectory(prefix='nv-round3-linus-') as tmp:
    tmp = Path(tmp)
    source = tmp / 'probe.m'
    binary = tmp / 'probe'
    source.write_text(template)
    cmd = ['xcrun', 'clang', '-arch', 'x86_64', '-mmacosx-version-min=10.13', '-fno-objc-arc', '-fblocks', '-Wno-deprecated-declarations', '-framework', 'Cocoa', str(source), '-o', str(binary)]
    subprocess.run(cmd, check=True)
    production = subprocess.run([str(binary)], capture_output=True, text=True, timeout=20)
    print(production.stdout + production.stderr, end='')
    # This control changes only the extracted translation unit, never production.
    normalized = template.replace('originalEncoding == fileEncoding &&', '(uint32_t)originalEncoding == (uint32_t)fileEncoding &&')
    source.write_text(normalized)
    subprocess.run(cmd, check=True)
    control = subprocess.run([str(binary)], capture_output=True, text=True, timeout=20)
    print('NORMALIZED-ENCODING CONTROL:')
    print(control.stdout + control.stderr, end='')
    if control.returncode:
        raise SystemExit(control.returncode)
    mutants = {
        'double_utf8_bom_skip': ('detectedEncoding == NSUTF8StringEncoding ? 0 : bomLength', 'bomLength'),
        'lost_conflict_origin': ('[coder encodeObject:sourceConflictOriginUUID forKey:VAR_STR(sourceConflictOriginUUID)];', '[coder encodeObject:nil forKey:VAR_STR(sourceConflictOriginUUID)];'),
        'cancel_retains_request': ('[pendingConversionRequests removeObjectForKey:key];\n}', '// intentionally retain cancelled request\n}'),
    }
    for name, (old, new) in mutants.items():
        assert old in normalized, name
        source.write_text(normalized.replace(old, new, 1))
        subprocess.run(cmd, check=True)
        result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=20)
        print(f'NEGATIVE CONTROL {name}: exit={result.returncode}')
        print(result.stdout + result.stderr, end='')
        if result.returncode == 0:
            raise SystemExit(f'Negative control did not fail: {name}')
    print('PASS: normalized-encoding control and three independently failing negative controls')
    raise SystemExit(production.returncode)
