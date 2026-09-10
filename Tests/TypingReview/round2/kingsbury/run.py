#!/usr/bin/env python3
"""Pause real main-queue completions immediately before delivery; exercise native storage."""
from pathlib import Path
import hashlib, json, os, subprocess
suite = Path(__file__).resolve().parent
repo = suite.parents[3]
out = repo / 'build/TypingReview/round2/kingsbury'
out.mkdir(parents=True, exist_ok=True)
session = (repo/'Sources/Editor/NVNoteEditingSession.m').read_text()
selectors = ['- (void)sourceCharactersChanged:', '- (void)sourceSyntaxChanged:', '- (void)sourceLayoutDidDetach', '- (NSDictionary *)snapshotForSourceAnalysis:', '- (void)sourceAnalysis:']
methods = '\n'.join(session[(start := session.index(s)):session.index('\n- (', start+1)] for s in selectors)
(out/'session.inc').write_text(methods)
attributed = (repo/'Sources/Editor/AttributedPlainText.m').read_text()
links = attributed[attributed.index('- (void)addLinkAttributesForRange:'):attributed.index('- (void)addStrikethroughNearDoneTagsForRange:')]
strings = (repo/'Sources/Utilities/NSString_NV.m').read_text()
escape = strings[strings.index('- (NSString*)stringWithPercentEscapes {'):strings.index('+ (NSString*)reasonStringFromCarbonFSError:')]
(out/'links.m').write_text('#import <Cocoa/Cocoa.h>\n#import <CoreServices/CoreServices.h>\n#import "AttributedPlainText.h"\n@interface NSString (ProbeEscape)\n- (NSString *)stringWithPercentEscapes;\n@end\n@implementation NSString (ProbeEscape)\n'+escape+'\n@end\nstatic BOOL _StringWithRangeIsProbablyObjC(NSString *string, NSRange range);\n@implementation NSMutableAttributedString (AttributedPlainText)\n'+links+'\n@end\n')
command=['xcrun','clang','-arch','x86_64','-mmacosx-version-min=10.13','-fblocks','-fno-objc-arc','-O1','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer','-Wno-deprecated-declarations','-Wno-incomplete-implementation','-I',str(repo/'Sources/Editor'),'-I',str(out),'-framework','Cocoa','-framework','CoreServices',str(out/'links.m'),str(repo/'Sources/Editor/NVSourceAnalysis.m'),str(suite/'probe.m'),'-o',str(out/'probe')]
env=dict(os.environ,ASAN_OPTIONS='detect_leaks=0:halt_on_error=1',UBSAN_OPTIONS='halt_on_error=1')
def run(name, body):
    (out/'session.inc').write_text(body)
    compiled=subprocess.run(command,capture_output=True,text=True,timeout=45)
    (out/(name+'-compile.log')).write_text(compiled.stdout+compiled.stderr)
    if compiled.returncode: raise SystemExit(compiled.stderr)
    result=subprocess.run([str(out/'probe')],capture_output=True,text=True,env=env,timeout=30)
    (out/(name+'-output.txt')).write_text(result.stdout+result.stderr)
    print(name+': '+result.stdout+result.stderr,end='')
    return result
result=run('production',methods)
needle='        [sourceAnalysis invalidate];'
assert methods.count(needle)==1
negative=run('negative-control-detach-without-invalidation',methods.replace(needle,'        /* negative control: no invalidation */'))
(out/'session.inc').write_text(methods)
report={'head':subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip(),'methods_sha256':hashlib.sha256(methods.encode()).hexdigest(),'production_exit':result.returncode,'negative_control_exit':negative.returncode,'passed':result.returncode==0 and negative.returncode!=0 and 'last detached layout cancels queued publication' in negative.stderr,'sanitizers':['address','undefined'],'compile_command':command}
(out/'results.json').write_text(json.dumps(report,indent=2)+'\n')
(suite/'results.json').write_text(json.dumps(report,indent=2)+'\n')
(suite/'output.txt').write_text(result.stdout+result.stderr+'\nNegative control:\n'+negative.stdout+negative.stderr)
raise SystemExit(0 if report['passed'] else 1)
