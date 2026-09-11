#!/usr/bin/env python3
"""Bounded frozen native hard-break indentation and soft-separator check."""
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
CURRENT="2ea92180939a3e51df8fe867ad548140ed455868"
BASE="75d6f4269d5c3f0ff2d3df392659ccf95bc1482b"
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
with tempfile.TemporaryDirectory(prefix="separator-platform-r2-",dir=HERE) as temporary:
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
        run(["xcrun","clang","-arch",arch,"-mmacosx-version-min="+minimum,"-fno-objc-arc","-fblocks",
             "-Wno-deprecated-declarations","-framework","Cocoa","-framework","CoreText","-I",str(temp),
             str(HERE/"probe.m"),str(temp/"NVSourceTypesetter.m"),"-o",str(binary)])
        result=run(["arch","-"+arch,str(binary),str(path)],check=False)
        observation=json.loads(path.read_text());observation.update(architecture=arch,minimum_os=minimum,exit_code=result.returncode,stdout=result.stdout,stderr=result.stderr)
        report["runs"].append(observation)
        print(arch+": "+result.stdout+result.stderr,end="")
(HERE/"results.json").write_text(json.dumps(report,indent=2)+"\n")
assert all(result["exit_code"]==0 for result in report["runs"]),"See results.json for failed observations"
