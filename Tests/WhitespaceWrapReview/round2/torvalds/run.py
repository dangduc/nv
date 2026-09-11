#!/usr/bin/env python3
"""Check the frozen glyph method and shared style integration with native AppKit."""
import hashlib,json,os,platform,subprocess
from pathlib import Path
suite=Path(__file__).resolve().parent
repo=suite.parents[3]
output=repo/'build/WhitespaceWrapReview/round2/torvalds'
output.mkdir(parents=True,exist_ok=True)
head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip()
reviewed_head='072a6bc0f54a52603f8cedfbcacc17d0ab836a36'
source=(repo/'Sources/Editor/LinkingEditor.m').read_text()
a=source.index('- (NSUInteger)layoutManager:(NSLayoutManager *)manager shouldGenerateGlyphs:')
b=source.index('\n}\n',a)+2
glyph=source[a:b]
prefs=(repo/'Sources/Preferences/GlobalPrefs.m').read_text()
a=prefs.index('\tstatic NSParagraphStyle *sourceStyle;')
b=prefs.index('\n}',a)
style=prefs[a:b]
assert hashlib.sha256(glyph.encode()).hexdigest()=='7a3c15d7e02a071f3f1bab9018e360f6b92decc7c48bb7ecd49189c179a188ef', 'reviewed glyph method changed'
assert hashlib.sha256(style.encode()).hexdigest()=='f9263d1675de92fde351aa09cc48fd9f7ff6a654332fa5df9644ff40d82fa993', 'reviewed style block changed'
helper=(repo/'Tests/WhitespaceWrapReview/round1/torvalds/probe.m').read_text()
helper=helper.replace('// EXTRACTED_PRODUCTION_METHOD',glyph)
extra=(suite/'style-probe.inc').read_text().replace('// EXTRACTED_STYLE_BLOCK',style)
helper=helper.replace('@interface ProductionDelegate',extra+'\n@interface ProductionDelegate',1)
helper=helper.replace('ProductionDelegate *delegate = [ProductionDelegate new];','StyleChecks();\n        ProductionDelegate *delegate = [ProductionDelegate new];',1)
old='attributes:@{NSFontAttributeName:[NSFont fontWithName:@"Times-Roman" size:14], NSLigatureAttributeName:@2}'
new='attributes:InstallProductionStyle([NSMutableDictionary dictionaryWithDictionary:@{NSFontAttributeName:[NSFont fontWithName:@"Times-Roman" size:14], NSLigatureAttributeName:@2}])'
assert old in helper
helper=helper.replace(old,new)
harness=output/'extracted-probe.m';harness.write_text(helper)
reports=[]
for arch in ('arm64','x86_64'):
 binary=output/('probe-'+arch)
 subprocess.run(['xcrun','clang','-arch',arch,'-mmacosx-version-min=13.0','-fno-objc-arc','-g','-O1','-fsanitize=address,undefined','-fno-sanitize-recover=all','-fno-omit-frame-pointer','-framework','Cocoa',str(harness),'-o',str(binary)],check=True)
 env=dict(os.environ,ASAN_OPTIONS='detect_leaks=0:abort_on_error=1',UBSAN_OPTIONS='halt_on_error=1:print_stacktrace=1')
 run=subprocess.run(['arch','-'+arch,str(binary)],env=env,capture_output=True,text=True,timeout=60)
 (output/('output-'+arch+'.txt')).write_text(run.stdout+run.stderr)
 print(run.stdout+run.stderr,end='');run.check_returncode()
 result=json.loads(run.stdout);result.update(architecture=arch,sanitizers=['ASan','UBSan'],simultaneous_style_callers=64)
 reports.append(result)
report={'head':head,'reviewed_head':reviewed_head,'glyph_method_sha256':hashlib.sha256(glyph.encode()).hexdigest(),'style_block_sha256':hashlib.sha256(style.encode()).hexdigest(),'macOS':platform.mac_ver()[0],'runs':reports}
for p in (output/'results.json',suite/'results.json'):p.write_text(json.dumps(report,indent=2)+'\n')
(suite/'output.txt').write_text(''.join((output/('output-'+a+'.txt')).read_text() for a in ('arm64','x86_64')))
print('PASS: round2 extracted production glyph and shared style integration')
