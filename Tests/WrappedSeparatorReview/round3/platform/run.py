#!/usr/bin/env python3
"""Frozen fast-path shaping comparison with strict deployment availability checks."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
CURRENT="e022109eaf2bad6583512c2ed2b48561d9dae011"
BASE="2ea92180939a3e51df8fe867ad548140ed455868"
def run(command,check=True):
    result=subprocess.run(command,cwd=ROOT,capture_output=True,text=True,timeout=45)
    if check and result.returncode: raise RuntimeError((command,result.returncode,result.stdout,result.stderr))
    return result
def source(revision,path): return run(["git","show",revision+":"+path]).stdout
def hook(text):
    start=text.index("- (NSUInteger)layoutManager:");end=text.index("{",start)+1;depth=1
    while depth: depth+=(text[end]=="{")-(text[end]=="}");end+=1
    return text[start:end]

report={"commit":CURRENT,"base":BASE,"host":run(["sw_vers"]).stdout,"xcode":run(["xcodebuild","-version"]).stdout,"runs":[]}
with tempfile.TemporaryDirectory(prefix="separator-platform-r3-",dir=HERE) as temporary:
    temp=Path(temporary);delegates=[]
    for revision,name in ((CURRENT,"CurrentDelegate"),(BASE,"BaseDelegate")):
        method=hook(source(revision,"Sources/Editor/LinkingEditor.m"))
        report[name+"_sha256"]=hashlib.sha256(method.encode()).hexdigest()
        delegates.append("@interface "+name+" : NSObject <NSLayoutManagerDelegate>\n@end\n@implementation "+name+"\n"+method+"\n@end\n")
    (temp/"delegates.h").write_text("\n".join(delegates))
    for name in ("NVSourceTypesetter.h","NVSourceTypesetter.m"):
        value=source(CURRENT,"Sources/Editor/"+name);(temp/name).write_text(value)
        report[name+"_sha256"]=hashlib.sha256(value.encode()).hexdigest()
    for arch,minimum in (("arm64","11.0"),("x86_64","10.13")):
        binary=temp/arch;path=temp/(arch+".json")
        command=["xcrun","clang","-arch",arch,"-mmacosx-version-min="+minimum,"-fno-objc-arc","-fblocks",
             "-Wno-deprecated-declarations","-Werror=unguarded-availability","-Werror=unguarded-availability-new",
             "-framework","Cocoa","-framework","CoreText","-I",str(temp),str(HERE/"probe.m"),str(temp/"NVSourceTypesetter.m"),"-o",str(binary)]
        compiled=run(command)
        load_commands=run(["otool","-l",str(binary)]).stdout
        match=re.search(r"cmd LC_VERSION_MIN_MACOSX\s+cmdsize \d+\s+version ([\d.]+)",load_commands) or re.search(r"cmd LC_BUILD_VERSION\s+cmdsize \d+\s+platform \S+\s+minos ([\d.]+)",load_commands)
        assert match and match.group(1)==minimum,(arch,load_commands)
        result=run(["arch","-"+arch,str(binary),str(path)],check=False)
        observation=json.loads(path.read_text());observation.update(architecture=arch,minimum_os=match.group(1),exit_code=result.returncode,
            compile_command=command,compiler_stderr=compiled.stderr,stdout=result.stdout,stderr=result.stderr)
        report["runs"].append(observation)
        print(arch+": "+result.stdout+result.stderr,end="")
(HERE/"results.json").write_text(json.dumps(report,indent=2)+"\n")
assert all(result["exit_code"]==0 for result in report["runs"]),"See results.json for failed observations"
