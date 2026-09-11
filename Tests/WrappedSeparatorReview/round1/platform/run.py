#!/usr/bin/env python3
"""Frozen AppKit paragraph/attachment probes and deployment metadata audit."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
CURRENT="9e6c8dd6adc058e7044f2c562532af97dd4e63d4"
BASE="75d6f4269d5c3f0ff2d3df392659ccf95bc1482b"

def run(command,check=True):
    result=subprocess.run(command,cwd=ROOT,capture_output=True,text=True,timeout=45)
    if check and result.returncode: raise RuntimeError((command,result.returncode,result.stdout,result.stderr))
    return result
def frozen(commit,path): return run(["git","show",commit+":"+path]).stdout
def hook(text):
    begin=text.index("- (NSUInteger)layoutManager:")
    end=text.index("{",begin)+1;depth=1
    while depth: depth+=(text[end]=="{")-(text[end]=="}");end+=1
    return text[begin:end]

report={"commit":CURRENT,"base":BASE,"host":run(["sw_vers"]).stdout,"xcode":run(["xcodebuild","-version"]).stdout,"runs":[]}
with tempfile.TemporaryDirectory(prefix="separator-platform-",dir=HERE) as temporary:
    temp=Path(temporary)
    delegates=[]
    for revision,name in ((CURRENT,"CurrentDelegate"),(BASE,"BaseDelegate")):
        method=hook(frozen(revision,"Sources/Editor/LinkingEditor.m"))
        report[name+"_sha256"]=hashlib.sha256(method.encode()).hexdigest()
        delegates.append("@interface "+name+" : NSObject <NSLayoutManagerDelegate>\n@end\n@implementation "+name+"\n"+method+"\n@end\n")
    (temp/"delegates.h").write_text("\n".join(delegates))
    for name in ("NVSourceTypesetter.h","NVSourceTypesetter.m"):
        source=frozen(CURRENT,"Sources/Editor/"+name)
        (temp/name).write_text(source)
        report[name+"_sha256"]=hashlib.sha256(source.encode()).hexdigest()
    for arch,minimum in (("arm64","11.0"),("x86_64","10.13")):
        binary=temp/arch
        command=["xcrun","clang","-arch",arch,"-mmacosx-version-min="+minimum,"-fno-objc-arc","-fblocks",
            "-Wno-deprecated-declarations","-Werror=unguarded-availability","-Werror=unguarded-availability-new",
            "-framework","Cocoa","-framework","CoreText","-I",str(temp),str(HERE/"probe.m"),str(temp/"NVSourceTypesetter.m"),"-o",str(binary)]
        compiled=run(command)
        load_commands=run(["otool","-l",str(binary)]).stdout
        match=re.search(r"cmd LC_VERSION_MIN_MACOSX\s+cmdsize \d+\s+version ([\d.]+)",load_commands) or re.search(r"cmd LC_BUILD_VERSION\s+cmdsize \d+\s+platform \S+\s+minos ([\d.]+)",load_commands)
        assert match and match.group(1)==minimum,(arch,match.group(1) if match else load_commands)
        path=temp/(arch+".json")
        result=run(["arch","-"+arch,str(binary),str(path)],check=False)
        observation=json.loads(path.read_text())
        (HERE/(arch+"-observations.json")).write_text(json.dumps(observation,indent=2)+"\n")
        report["runs"].append({"architecture":arch,"minimum_os":match.group(1),"compile_command":command,
             "compiler_stderr":compiled.stderr,"runtime_stdout":result.stdout,"runtime_stderr":result.stderr,"exit_code":result.returncode,
             "checks":observation["checks"],"comparisons":observation["comparisons"],"baselineDifferences":observation["baselineDifferences"],"failures":observation["failures"]})
        print(arch+": "+result.stdout+result.stderr,end="")
(HERE/"results.json").write_text(json.dumps(report,indent=2)+"\n")
assert all(run["exit_code"]==0 for run in report["runs"]),"See results.json for failed observations"
