#!/usr/bin/env python3
"""Run scratch-boundary and lifetime checks on the reviewed production method."""
import hashlib,json,os,platform,subprocess
from pathlib import Path
suite=Path(__file__).resolve().parent;repo=suite.parents[3]
output=repo/'build/WhitespaceWrapReview/round3/torvalds';output.mkdir(parents=True,exist_ok=True)
reviewed='4b725372670afd5f5ecadf512deba8498336b2f0'
def glyph_method(s):
 a=s.index('- (NSUInteger)layoutManager:(NSLayoutManager *)manager shouldGenerateGlyphs:');return s[a:s.index('\n}\n',a)+2]
def style_block(s):
 a=s.index('\tstatic NSParagraphStyle *sourceStyle;');return s[a:s.index('\n}',a)]
glyph=glyph_method((repo/'Sources/Editor/LinkingEditor.m').read_text())
expected=glyph_method(subprocess.check_output(['git','show',reviewed+':Sources/Editor/LinkingEditor.m'],cwd=repo,text=True));assert glyph==expected,'reviewed glyph method changed'
style=style_block((repo/'Sources/Preferences/GlobalPrefs.m').read_text())
expectedstyle=style_block(subprocess.check_output(['git','show',reviewed+':Sources/Preferences/GlobalPrefs.m'],cwd=repo,text=True));assert style==expectedstyle,'reviewed style changed'
old=(repo/'Tests/WhitespaceWrapReview/round1/torvalds/probe.m').read_text()
header=old[:old.index('static void RunVector(')].replace('// EXTRACTED_PRODUCTION_METHOD',glyph)
native=old[old.index('static NSDictionary *NativeGlyphs('):old.index('int main(void)')]
native=native.replace('NSLayoutManager *manager = [NSLayoutManager new];','NSLayoutManager *manager = [AuditNativeLayout new];').replace('[manager ensureGlyphsForCharacterRange:NSMakeRange(0,text.length)];','[manager ensureGlyphsForCharacterRange:NSMakeRange(0,text.length)];\n    ClobberStack();')
native=native.replace('attributes:@{NSFontAttributeName:[NSFont fontWithName:@"Times-Roman" size:14], NSLigatureAttributeName:@2}', 'attributes:InstallStyle([NSMutableDictionary dictionaryWithDictionary:@{NSFontAttributeName:[NSFont fontWithName:@"Times-Roman" size:14], NSLigatureAttributeName:@2}])')
body=(suite/'probe.m').read_text().replace('// NATIVE_GLYPH_HELPER',native)
harness=output/'extracted-probe.m';harness.write_text(header+'\nstatic NSDictionary *InstallStyle(NSMutableDictionary *noteBodyAttributes) {\n'+style+'\n}\n'+body)
reports=[]
for arch in ('arm64','x86_64'):
 binary=output/('probe-'+arch)
 subprocess.run(['xcrun','clang','-arch',arch,'-mmacosx-version-min=13.0','-fno-objc-arc','-g','-O1','-fsanitize=address,undefined','-fsanitize-address-use-after-return=always','-fno-sanitize-recover=all','-fno-omit-frame-pointer','-framework','Cocoa',str(harness),'-o',str(binary)],check=True)
 env=dict(os.environ,ASAN_OPTIONS='detect_leaks=0:detect_stack_use_after_return=1:abort_on_error=1',UBSAN_OPTIONS='halt_on_error=1:print_stacktrace=1')
 run=subprocess.run(['arch','-'+arch,str(binary)],env=env,capture_output=True,text=True,timeout=60)
 (output/('output-'+arch+'.txt')).write_text(run.stdout+run.stderr);print(run.stdout+run.stderr,end='');run.check_returncode()
 r=json.loads(run.stdout);r.update(architecture=arch,sanitizers=['ASan (stack use after return enabled)','UBSan']);reports.append(r)
r={'reviewed_head':reviewed,'head':subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip(),'glyph_method_sha256':hashlib.sha256(glyph.encode()).hexdigest(),'style_block_sha256':hashlib.sha256(style.encode()).hexdigest(),'macOS':platform.mac_ver()[0],'runs':reports}
for p in (output/'results.json',suite/'results.json'):p.write_text(json.dumps(r,indent=2)+'\n')
(suite/'output.txt').write_text(''.join((output/('output-'+a+'.txt')).read_text()for a in ('arm64','x86_64')))
print('PASS: round3 stack/heap boundary and native scratch lifetime checks')
