#!/usr/bin/env python3
"""Check production cleanup at partial paragraph completion, without windows."""
import hashlib
import json
from pathlib import Path
import platform
import subprocess

repo=Path(__file__).resolve().parents[4]
suite=Path(__file__).parent
out=repo/"build/WordWrapReview/round2/ousterhout"
out.mkdir(parents=True,exist_ok=True)
existing=(repo/"Tests/WordWrapping/run.py").read_text()
helper=existing[existing.index("def glyph_delegate("):existing.index("parser = argparse")]
namespace={}
exec(helper,namespace)
hook=namespace["glyph_delegate"]((repo/"Sources/Editor/LinkingEditor.m").read_text())
(out/"space-delegate.h").write_text("@interface SpaceDelegate : NSObject <NSLayoutManagerDelegate>\n@end\n@implementation SpaceDelegate\n"+hook+"\n@end\n")
runs=[]
for architecture in (["arm64","x86_64"] if platform.machine()=="arm64" else ["x86_64"]):
    binary=out/("probe-"+architecture)
    subprocess.run(["xcrun","clang","-arch",architecture,"-mmacosx-version-min="+("11.0" if architecture=="arm64" else "10.13"),"-fno-objc-arc","-Wno-deprecated-declarations","-Wall","-Wextra","-Wno-unused-parameter","-framework","Cocoa","-framework","CoreText","-I",str(out),"-I",str(repo/"Sources/Editor"),str(suite/"probe.m"),str(repo/"Sources/Editor/NVSourceTypesetter.m"),"-o",str(binary)],check=True)
    path=out/(architecture+".json")
    result=subprocess.run(["arch","-"+architecture,str(binary),str(path)],capture_output=True,text=True,timeout=60)
    (out/(architecture+".log")).write_text(result.stdout+result.stderr)
    print(result.stdout+result.stderr,end="")
    result.check_returncode()
    record=json.loads(path.read_text());record["architecture"]=architecture
    negative=subprocess.run(["arch","-"+architecture,str(binary),str(out/(architecture+"-negative.json")),"omit-cleanup"],capture_output=True,text=True,timeout=60)
    (out/(architecture+"-negative.log")).write_text(negative.stdout+negative.stderr)
    assert negative.returncode==1 and "paragraph completion releases analysis" in negative.stderr,negative
    record["negativeControl"]={"exitCode":negative.returncode,"failure":negative.stderr.strip()}
    print("PASS: omission of completion cleanup rejected ("+architecture+")")
    runs.append(record)
(suite/"results.json").write_text(json.dumps({"revision":subprocess.check_output(["git","rev-parse","HEAD"],cwd=repo,text=True).strip(),"production_sha256":hashlib.sha256((repo/"Sources/Editor/NVSourceTypesetter.m").read_bytes()).hexdigest(),"runs":runs},indent=2)+"\n")
