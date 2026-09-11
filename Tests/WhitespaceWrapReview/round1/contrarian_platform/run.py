#!/usr/bin/env python3
"""Compare native paragraph/font scope using the extracted production glyph delegate."""
import fcntl
import hashlib
import json
from pathlib import Path
import subprocess

suite=Path(__file__).resolve().parent
repo=suite.parents[3]
output=repo/'build/WhitespaceWrapReview/round1/contrarian_platform'
output.mkdir(parents=True,exist_ok=True)
source=(repo/'Sources/Editor/LinkingEditor.m').read_text()
start=source.index('- (NSUInteger)layoutManager:(NSLayoutManager *)manager shouldGenerateGlyphs:')
end=source.index('\n}\n',start)+2
method=source[start:end]
harness=output/'extracted-probe.m'
harness.write_text((suite/'probe.m').read_text().replace('// EXTRACTED_PRODUCTION_METHOD',method))
binary=output/'probe-x86_64'
subprocess.run(['xcrun','clang','-arch','x86_64','-mmacosx-version-min=13.0','-fno-objc-arc','-O1','-framework','Cocoa',str(harness),'-o',str(binary)],check=True)
# No windows or application process are created. Lock also excludes simultaneous desktop probes.
with Path('/Users/duc/dev/nv/build/pr-review/gui.lock').open('a') as lock:
    fcntl.flock(lock,fcntl.LOCK_EX)
    run=subprocess.run(['arch','-x86_64',str(binary),str(output/'results.json')],capture_output=True,text=True,timeout=60)
(output/'output.txt').write_text(run.stdout+run.stderr)
print(run.stdout+run.stderr,end='')
if run.returncode: raise SystemExit(run.returncode)
report=json.loads((output/'results.json').read_text())
report.update(head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip(),method_sha256=hashlib.sha256(method.encode()).hexdigest(),architecture='x86_64',macOS=subprocess.check_output(['sw_vers','-productVersion'],text=True).strip())
(output/'results.json').write_text(json.dumps(report,indent=2)+'\n')
(suite/'results.json').write_text(json.dumps(report,indent=2)+'\n')
(suite/'output.txt').write_text(run.stdout+run.stderr)
for row in report['cases']:
    print(row['configuration'],row['fixture'],row['baseLineCount'],row['fixedLineCount'],row['sameGeometry'],row['afterFontBaseLineCount'],row['afterFontFixedLineCount'])
