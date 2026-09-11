#!/usr/bin/env python3
"""Compare the real pre/post optimization hooks through a new composition history."""
import hashlib
import json
from pathlib import Path
import platform
import subprocess
import tempfile

HERE=Path(__file__).resolve().parent
REPO=HERE.parents[3]
COMMIT="e022109eaf2bad6583512c2ed2b48561d9dae011"
PREVIOUS="2ea92180939a3e51df8fe867ad548140ed455868"
ORIGINAL="75d6f42"
def frozen(path,revision=COMMIT):return subprocess.check_output(["git","show",revision+":"+path],cwd=REPO,text=True)
def hook(revision):
    source=frozen("Sources/Editor/LinkingEditor.m",revision)
    start=source.index("- (NSUInteger)layoutManager:");end=source.index("{",start)+1;depth=1
    while depth:
        depth+=(source[end]=="{")-(source[end]=="}");end+=1
    return source[start:end]
typesetter=frozen("Sources/Editor/NVSourceTypesetter.m")
assert typesetter==frozen("Sources/Editor/NVSourceTypesetter.m",PREVIOUS)
assert typesetter==frozen("Sources/Editor/NVSourceTypesetter.m",ORIGINAL)
literal_hook=hook(ORIGINAL)
setup=frozen("Tests/WrappedSeparatorReview/round1/ux/probe.m").split("static void AroundSeparator(")[0]
setup=setup.replace('"../../../WordWrapReview/round1/contrarian_ux/probe.m"','"'+str(REPO/"Tests/WordWrapReview/round1/contrarian_ux/probe.m")+'"')
round2=frozen("Tests/WrappedSeparatorReview/round2/ux/probe.m")
setup+=round2[round2.index("static void PrepareNativeTyping("):round2.index("static void ObserveEdit(")]
runs=[]
with tempfile.TemporaryDirectory(prefix="nvalt-r3-separator-ux-") as temporary:
    root=Path(temporary)
    (root/"reused-ux-helper.h").write_text(setup)
    (root/"original-literal-delegate.h").write_text("@interface LiteralSpaceDelegate : NSObject <NSLayoutManagerDelegate>\n@end\n@implementation LiteralSpaceDelegate\n"+literal_hook+"\n@end\n")
    (root/"NVSourceTypesetter.h").write_text(frozen("Sources/Editor/NVSourceTypesetter.h"));(root/"typesetter.m").write_text(typesetter)
    for arch in (["arm64","x86_64"] if platform.machine()=="arm64" else ["x86_64"]):
        for mode,revision in (("optimized",COMMIT),("previous",PREVIOUS)):
            glyphs=hook(revision)
            (root/"production-space-delegate.h").write_text("@interface SpaceDelegate : NSObject <NSLayoutManagerDelegate>\n@end\n@implementation SpaceDelegate\n"+glyphs+"\n@end\n")
            binary=root/(arch+"-"+mode);result=root/(arch+"-"+mode+".json")
            subprocess.run(["xcrun","clang","-arch",arch,"-mmacosx-version-min="+("11.0" if arch=="arm64" else "10.13"),
                "-fno-objc-arc","-Wno-deprecated-declarations","-Wall","-Wextra","-Wno-unused-parameter","-Wno-unused-variable","-Wno-unused-function","-I",str(root),
                "-framework","Cocoa","-framework","CoreText",str(HERE/"probe.m"),str(root/"typesetter.m"),"-o",str(binary)],check=True)
            run=subprocess.run(["arch","-"+arch,str(binary),str(result)],capture_output=True,text=True,timeout=60)
            print(arch+" "+mode+": "+run.stdout+run.stderr,end="");run.check_returncode()
            record=json.loads(result.read_text());transcript=record.pop("transcript")
            record.update(architecture=arch,mode=mode,glyph_hook_sha256=hashlib.sha256(glyphs.encode()).hexdigest(),
                transcript_sha256=hashlib.sha256(json.dumps(transcript,sort_keys=True).encode()).hexdigest())
            record["firstHistory"]=[{k:v for k,v in item.items() if k!="positions"} for item in transcript[:6]]
            runs.append(record)
(HERE/"results.json").write_text(json.dumps({"revision":COMMIT,"previous_revision":PREVIOUS,"original_literal_revision":ORIGINAL,
    "original_literal_hook_sha256":hashlib.sha256(literal_hook.encode()).hexdigest(),"host":platform.mac_ver()[0],
    "typesetter_sha256":hashlib.sha256(typesetter.encode()).hexdigest(),"runs":runs},indent=2)+"\n")
for current,previous in zip(runs[::2],runs[1::2]):
    assert current["failures"]==previous["failures"]==0,(current["failureKinds"],previous["failureKinds"])
    assert current["transcript_sha256"]==previous["transcript_sha256"],"Optimization changes source, selection, affinity, space properties, or insertion positions."
