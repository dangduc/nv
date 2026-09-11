#!/usr/bin/env python3
"""Run bounded deletion/replacement histories through native text views."""
import hashlib
import json
from pathlib import Path
import platform
import subprocess
import tempfile

HERE=Path(__file__).resolve().parent
REPO=HERE.parents[3]
COMMIT="2ea92180939a3e51df8fe867ad548140ed455868"
def frozen(path):return subprocess.check_output(["git","show",COMMIT+":"+path],cwd=REPO,text=True)
editor=frozen("Sources/Editor/LinkingEditor.m")
start=editor.index("- (NSUInteger)layoutManager:");end=editor.index("{",start)+1;depth=1
while depth:
    depth+=(editor[end]=="{")-(editor[end]=="}");end+=1
hook=editor[start:end];typesetter=frozen("Sources/Editor/NVSourceTypesetter.m")
helper=frozen("Tests/WrappedSeparatorReview/round1/ux/probe.m").split("static void AroundSeparator(")[0]
helper=helper.replace('"../../../WordWrapReview/round1/contrarian_ux/probe.m"','"'+str(REPO/"Tests/WordWrapReview/round1/contrarian_ux/probe.m")+'"')
runs=[]
with tempfile.TemporaryDirectory(prefix="nvalt-r2-separator-ux-") as temporary:
    root=Path(temporary)
    (root/"round1-ux-helper.h").write_text(helper)
    (root/"production-space-delegate.h").write_text("@interface SpaceDelegate : NSObject <NSLayoutManagerDelegate>\n@end\n@implementation SpaceDelegate\n"+hook+"\n@end\n")
    (root/"NVSourceTypesetter.h").write_text(frozen("Sources/Editor/NVSourceTypesetter.h"));(root/"typesetter.m").write_text(typesetter)
    for arch in (["arm64","x86_64"] if platform.machine()=="arm64" else ["x86_64"]):
        binary=root/arch;result=root/(arch+".json")
        subprocess.run(["xcrun","clang","-arch",arch,"-mmacosx-version-min="+("11.0" if arch=="arm64" else "10.13"),
            "-fno-objc-arc","-Wno-deprecated-declarations","-Wall","-Wextra","-Wno-unused-parameter","-Wno-unused-variable","-I",str(root),
            "-framework","Cocoa","-framework","CoreText",str(HERE/"probe.m"),str(root/"typesetter.m"),"-o",str(binary)],check=True)
        run=subprocess.run(["arch","-"+arch,str(binary),str(result)],capture_output=True,text=True,timeout=60)
        print(arch+": "+run.stdout+run.stderr,end="");run.check_returncode()
        record=json.loads(result.read_text());record["architecture"]=arch;runs.append(record)
(HERE/"results.json").write_text(json.dumps({"revision":COMMIT,"host":platform.mac_ver()[0],"glyph_hook_sha256":hashlib.sha256(hook.encode()).hexdigest(),
    "typesetter_sha256":hashlib.sha256(typesetter.encode()).hexdigest(),"runs":runs},indent=2)+"\n")
for run in runs:assert run["failures"]==0,run["failureKinds"]
