#!/usr/bin/env python3
"""Measure frozen old/new wiki scan and flavor lookup; no GUI or user files."""
from pathlib import Path
import json, plistlib, shutil, statistics, subprocess, tempfile, time
ROOT = Path(__file__).resolve().parents[4]
OUT = Path(__file__).resolve().parent
OLD = 'bd74bf3'
NEW = '2dbfd46'
def source(ref, path):
    return subprocess.check_output(['git', 'show', f'{ref}:{path}'], cwd=ROOT, text=True)
def scan(s):
    start = s.index('- (void)_addDoubleBracketedNVLinkAttributesForRange:')
    return s[start:s.index('\nstatic BOOL _StringWithRangeIsProbablyObjC', start)]
new = source(NEW, 'Sources/Editor/AttributedPlainText.m')
helper_start = new.index('\nstatic BOOL _StringWithRangeIsProbablyObjC', new.index('- (void)_addDoubleBracketedNVLinkAttributesForRange:'))
helper = new[helper_start:new.index('- (void)addStrikethroughNearDoneTagsForRange:', helper_start)]
strings = source(NEW, 'Sources/Utilities/NSString_NV.m')
escape = strings[strings.index('- (NSString*)stringWithPercentEscapes {'):strings.index('+ (NSString*)reasonStringFromCarbonFSError:')]
code = '#import <Cocoa/Cocoa.h>\n#import <time.h>\n#import <stdint.h>\n' + source(NEW, 'Sources/Application/NVAppIdentity.h') + '''
@interface NSString (BenchEscape)
- (NSString *)stringWithPercentEscapes;
@end
@implementation NSString (BenchEscape)
''' + escape + '''
@end
static BOOL _StringWithRangeIsProbablyObjC(NSString *, NSRange);
@interface NSMutableAttributedString (Bench)
- (void)oldScan:(NSRange)r;
- (void)newScan:(NSRange)r;
@end
@implementation NSMutableAttributedString (Bench)
''' + scan(source(OLD, 'Sources/Editor/AttributedPlainText.m')).replace('_addDoubleBracketedNVLinkAttributesForRange:', 'oldScan:') + scan(new).replace('_addDoubleBracketedNVLinkAttributesForRange:', 'newScan:') + '\n@end\n' + helper + '''
static volatile uintptr_t sink;
static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec+t.tv_nsec/1e9; }
int main(void) {
 @autoreleasepool {
  printf("flavor=%s scheme=%s\\n", [[[[NSBundle mainBundle] infoDictionary] objectForKey:@"NVBuildFlavor"] UTF8String], [NVNoteURLScheme() UTF8String]);
  for (int rep=0; rep<7; rep++) {
   double t=now();
   for(int i=0; i<500000; i++) sink=(uintptr_t)NVNoteURLScheme();
   printf("helper,%d,%.6f\\n", rep, (now()-t)*1e9/500000);
  }
  int sizes[] = {0, 10, 1000, 10000};
  for(int size=0; size<4; size++) {
   NSMutableString *s=[NSMutableString string];
   for(int i=0;i<sizes[size];i++) [s appendFormat:@"[[Note %d]] body text\\n", i];
   if (!sizes[size]) [s appendString:@"No links in this ordinary note."];
   for(int rep=0; rep<9; rep++) {
    for(int order=0;order<2;order++) {
     int mode=(order+rep)%2;
     @autoreleasepool {
      NSMutableAttributedString *a=[[NSMutableAttributedString alloc] initWithString:s];
      double t=now();
      if(mode) [a newScan:NSMakeRange(0,[a length])]; else [a oldScan:NSMakeRange(0,[a length])];
      double elapsed=(now()-t)*1000;
      __block NSUInteger links=0;
      [a enumerateAttribute:NSLinkAttributeName inRange:NSMakeRange(0,a.length) options:0 usingBlock:^(id val,NSRange r,BOOL *stop) { if(val) links++; }];
      if(links != sizes[size]) { fprintf(stderr,"link count mismatch\\n"); return 1; }
      if(links) {
       NSString *scheme=[[a attribute:NSLinkAttributeName atIndex:2 effectiveRange:NULL] scheme];
       NSString *expected=mode?NVNoteURLScheme():@"nvalt";
       if(![scheme isEqualToString:expected]) { fprintf(stderr,"wrong scheme\\n"); return 1; }
      }
      printf("scan,%d,%d,%s,%.6f\\n", sizes[size], rep, mode?"new":"old", elapsed);
      [a release];
     }
    }
   }
  }
 }
 return 0;
}
'''
report={'base':OLD,'head':NEW,'architecture':'x86_64 (Rosetta on arm64)','environment':subprocess.check_output(['sw_vers'],text=True).strip(),'xcode':subprocess.check_output(['xcodebuild','-version'],text=True).strip(),'flavors':{}}
with tempfile.TemporaryDirectory(prefix='nvalt-luu-review-') as td:
    td=Path(td)
    (td/'probe.m').write_text(code)
    subprocess.run(['xcrun','clang','-arch','x86_64','-O2','-fno-objc-arc','-fblocks','-Wno-deprecated-declarations','-framework','Cocoa','-framework','CoreServices',str(td/'probe.m'),'-o',str(td/'probe')],check=True)
    for flavor in ['development','release']:
        app=td/(flavor+'.app')
        executable=app/'Contents/MacOS/probe'
        executable.parent.mkdir(parents=True)
        shutil.copy2(td/'probe',executable)
        (app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable':'probe','CFBundleIdentifier':'org.nvalt.luu-review.'+flavor,'CFBundlePackageType':'APPL','NVBuildFlavor':flavor}))
        output=subprocess.check_output([str(executable)],text=True)
        (OUT/(flavor+'-raw.txt')).write_text(output)
        helper_values=[]
        scans={}
        for line in output.splitlines():
            parts=line.split(',')
            if parts[0]=='helper' and int(parts[1])>0: helper_values.append(float(parts[2]))
            if parts[0]=='scan' and int(parts[2])>0: scans.setdefault(parts[1],{}).setdefault(parts[3],[]).append(float(parts[4]))
        flavor_report={'helper_ns_median':statistics.median(helper_values),'scans':{}}
        for n,modes in scans.items():
            med={m:statistics.median(v) for m,v in modes.items()}
            flavor_report['scans'][n]={'median_ms':med,'new_to_old_ratio':med['new']/med['old'] if med['old'] else None,'added_ms':med['new']-med['old']}
        report['flavors'][flavor]=flavor_report
# Confirm identity scripts on the actual built products without launching them.
products=ROOT/'build/DerivedData/Build/Products'
report['artifacts']={}
for flavor,path in [('development',products/'Development/nvALT Development.app'),('release',products/'ForBuilding/nvALT.app')]:
    p=subprocess.run(['python3',str(ROOT/'.github/scripts/check-app-identity.py'),str(path),flavor],capture_output=True,text=True)
    assert p.returncode==0,p.stdout+p.stderr
    report['artifacts'][flavor]={'bytes':sum(f.stat().st_size for f in path.rglob('*') if f.is_file()),'identity_check':p.stdout.strip()}
objroot=ROOT/'build/DerivedData/Build/Intermediates.noindex/Notation.build'
report['compile_objects']={p.name:len(list(p.rglob('*.o'))) for p in objroot.iterdir() if p.is_dir()}
(OUT/'results.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
print('PASS: old/new source scans produced expected link counts and flavor schemes; built product identity checks passed')
