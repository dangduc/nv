#!/usr/bin/env python3
"""Run memory and native glyph checks against the exact extracted production method."""
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess

suite = Path(__file__).resolve().parent
repo = suite.parents[3]
output = repo / 'build/WhitespaceWrapReview/round1/torvalds'
output.mkdir(parents=True, exist_ok=True)
source = (repo / 'Sources/Editor/LinkingEditor.m').read_text()
start = source.index('- (NSUInteger)layoutManager:(NSLayoutManager *)manager shouldGenerateGlyphs:')
end = source.index('\n}\n', start) + 2
method = source[start:end]
assert method.count('setGlyphs:') == 1
harness = output / 'extracted-probe.m'
harness.write_text((suite / 'probe.m').read_text().replace('// EXTRACTED_PRODUCTION_METHOD', method))
reports = []
for arch in ('arm64', 'x86_64'):
    binary = output / ('probe-' + arch)
    command = ['xcrun','clang','-arch',arch,'-mmacosx-version-min=13.0','-fno-objc-arc','-g','-O1',
               '-fsanitize=address,undefined','-fno-sanitize-recover=all','-fno-omit-frame-pointer',
               '-framework','Cocoa',str(harness),'-o',str(binary)]
    subprocess.run(command,check=True)
    environment = dict(os.environ, ASAN_OPTIONS='detect_leaks=0:abort_on_error=1', UBSAN_OPTIONS='halt_on_error=1:print_stacktrace=1')
    result = subprocess.run(['arch','-'+arch,str(binary)],text=True,capture_output=True,env=environment,timeout=60)
    (output / ('output-'+arch+'.txt')).write_text(result.stdout+result.stderr)
    print(result.stderr,end='')
    print(result.stdout,end='')
    if result.returncode:
        raise SystemExit(result.returncode)
    report = json.loads(result.stdout)
    report.update(architecture=arch, sanitizers=['ASan','UBSan'], native_exit=result.returncode)
    reports.append(report)
report = {'head':subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip(),
          'method_sha256':hashlib.sha256(method.encode()).hexdigest(), 'method_start_line':source[:start].count('\n')+1,
          'macOS':platform.mac_ver()[0], 'runs':reports}
(output/'results.json').write_text(json.dumps(report,indent=2)+'\n')
(suite/'results.json').write_text(json.dumps(report,indent=2)+'\n')
(suite/'output.txt').write_text(''.join((output/('output-'+a+'.txt')).read_text() for a in ('arm64','x86_64')))
print('PASS: extracted production method, both architectures, ASan and UBSan')
