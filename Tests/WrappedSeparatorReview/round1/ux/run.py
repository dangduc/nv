#!/usr/bin/env python3
"""Probe native caret commands and hit-testing at collapsed source separators."""
import hashlib
import json
from pathlib import Path
import platform
import subprocess
import tempfile

HERE=Path(__file__).resolve().parent
REPO=HERE.parents[3]
COMMIT="9e6c8dd6adc058e7044f2c562532af97dd4e63d4"
def frozen(path):
    return subprocess.check_output(["git","show",COMMIT+":"+path],cwd=REPO,text=True)
editor=frozen("Sources/Editor/LinkingEditor.m")
start=editor.index("- (NSUInteger)layoutManager:");end=editor.index("{",start)+1;depth=1
while depth:
    depth+=(editor[end]=="{")-(editor[end]=="}");end+=1
hook=editor[start:end]
typesetter=frozen("Sources/Editor/NVSourceTypesetter.m")
runs=[]
with tempfile.TemporaryDirectory(prefix="nvalt-separator-ux-") as temporary:
    root=Path(temporary)
    (root/"production-space-delegate.h").write_text("@interface SpaceDelegate : NSObject <NSLayoutManagerDelegate>\n@end\n@implementation SpaceDelegate\n"+hook+"\n@end\n")
    (root/"NVSourceTypesetter.h").write_text(frozen("Sources/Editor/NVSourceTypesetter.h"))
    (root/"typesetter.m").write_text(typesetter)
    for architecture in (["arm64","x86_64"] if platform.machine()=="arm64" else ["x86_64"]):
        binary=root/architecture;result=root/(architecture+".json")
        subprocess.run(["xcrun","clang","-arch",architecture,"-mmacosx-version-min="+("11.0" if architecture=="arm64" else "10.13"),
            "-fno-objc-arc","-Wno-deprecated-declarations","-Wall","-Wextra","-Wno-unused-parameter","-I",str(root),
            "-framework","Cocoa","-framework","CoreText",str(HERE/"probe.m"),str(root/"typesetter.m"),"-o",str(binary)],check=True)
        run=subprocess.run(["arch","-"+architecture,str(binary),str(result)],capture_output=True,text=True,timeout=60)
        print(architecture+": "+run.stdout+run.stderr,end="");run.check_returncode()
        record=json.loads(result.read_text());records=record.pop("records")
        record["records_sha256"]=hashlib.sha256(json.dumps(records,sort_keys=True).encode()).hexdigest()
        record["architecture"]=architecture;runs.append(record)
        (HERE/(architecture+"-geometry.json")).write_text(json.dumps(records,indent=2)+"\n")
(HERE/"results.json").write_text(json.dumps({"revision":COMMIT,"host":platform.mac_ver()[0],
    "glyph_hook_sha256":hashlib.sha256(hook.encode()).hexdigest(),"typesetter_sha256":hashlib.sha256(typesetter.encode()).hexdigest(),"runs":runs},indent=2)+"\n")
for record in runs:
    assert record["failures"]==0,record["failureKinds"]
