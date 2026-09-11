#!/usr/bin/env python3
"""Three shared production layouts: request order and targeted invalidation."""
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

HERE=Path(__file__).resolve().parent
REPO=HERE.parents[3]
COMMIT="2ea92180939a3e51df8fe867ad548140ed455868"


def source(path):
    return subprocess.check_output(["git","show",f"{COMMIT}:{path}"],cwd=REPO,text=True)


editor=source("Sources/Editor/LinkingEditor.m")
start=editor.index("- (NSUInteger)layoutManager:")
opening=editor.index("{",start)
assert "shouldGenerateGlyphs:" in editor[start:opening]
depth=1
end=opening+1
while depth:
    depth+=(editor[end]=="{")-(editor[end]=="}")
    end+=1
hook=editor[start:end]
typesetter=source("Sources/Editor/NVSourceTypesetter.m")
report={"commit":COMMIT,"base":"75d6f42","environment":subprocess.check_output(["sw_vers"],text=True).strip(),
        "xcode":subprocess.check_output(["xcodebuild","-version"],text=True).strip(),
        "production_hashes":{"glyph_hook":hashlib.sha256(hook.encode()).hexdigest(),
                             "typesetter":hashlib.sha256(typesetter.encode()).hexdigest()},"runs":{}}
with tempfile.TemporaryDirectory(prefix="ousterhout-separator-round2-") as temporary:
    root=Path(temporary)
    (root/"probe.m").write_text((HERE/"probe.m").read_text())
    (root/"support.h").write_text((HERE/"support.h").read_text().replace("@PRODUCTION_HOOK@",hook))
    (root/"NVSourceTypesetter.m").write_text(typesetter)
    (root/"NVSourceTypesetter.h").write_text(source("Sources/Editor/NVSourceTypesetter.h"))
    for arch,minimum in (("arm64","11.0"),("x86_64","10.13")):
        binary=root/("probe-"+arch)
        subprocess.run(["xcrun","clang","-arch",arch,"-mmacosx-version-min="+minimum,
                        "-fno-objc-arc","-fblocks","-Wno-deprecated-declarations","-Wall","-Wextra",
                        "-Wno-unused-parameter","-framework","Cocoa","-framework","CoreText","-I",str(root),
                        str(root/"probe.m"),str(root/"NVSourceTypesetter.m"),"-o",str(binary)],check=True)
        result=root/(arch+".json")
        run=subprocess.run(["arch","-"+arch,str(binary),str(result)],capture_output=True,text=True,timeout=30)
        print(arch,run.stdout,end="",flush=True)
        if run.stderr: print(run.stderr,end="",flush=True)
        run.check_returncode()
        report["runs"][arch]={"stdout":run.stdout,"stderr":run.stderr,**json.loads(result.read_text())}
(HERE/"results.json").write_text(json.dumps(report,indent=2)+"\n")
print("PASS: both architectures used frozen production hook and typesetter")
