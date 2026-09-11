#!/usr/bin/env python3
"""Check production Unicode URL escaping and current installation documentation."""
import ast
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

HERE=Path(__file__).resolve().parent
REPO=HERE.parents[3]
frozen="3a3dc4fb7194b5ea7189295a7bbd17393bb32038"
assert subprocess.check_output(["git","rev-parse","HEAD"],cwd=REPO,text=True).strip()==frozen
# Reuse only the round-one extractor and collaborators. Do not run its entry point.
prior=HERE.parent.parent / "round1/ux"
parsed=ast.parse((prior/"run.py").read_text())
extractor=next(node for node in parsed.body if isinstance(node,ast.FunctionDef) and node.name=="method")
namespace={"REPO":REPO,"re":__import__("re")}
exec(compile(ast.Module(body=[extractor],type_ignores=[]),str(prior/"run.py"),"exec"),namespace)
method=namespace["method"]
code=(prior/"probe.m").read_text().split("int main(")[0]
code=code.replace("// fixture implementations; URL escaping correctness is outside these hypotheses.","// production implementations. UUID base64 uses the original fixture helper.")
code=code.replace("- (NSString *)stringWithPercentEscapes { return [self stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLPathAllowedCharacterSet]]; }",
    method("Sources/Utilities/NSString_NV.m","- (NSString*)stringWithPercentEscapes"))
code=code.replace('- (NSString *)URLEncodedString { return [@"NV=" stringByAppendingString:self[@"NV"]]; }',
    method("Sources/Utilities/NSCollection_utils.m","- (NSString*)URLEncodedString"))
for marker,path,signature in (
    ("@NOTE_LINK@","Sources/Model/NoteObject.m","- (NSURL*)uniqueNoteLink"),
    ("@WIKI_LINK@","Sources/Editor/AttributedPlainText.m","- (void)_addDoubleBracketedNVLinkAttributesForRange:"),
    ("@CLICK_LINK@","Sources/Editor/LinkingEditor.m","- (void)clickedOnLink:")):
    code=code.replace(marker,method(path,signature))
code+=(HERE/"probe.m").read_text()
records=[]
with tempfile.TemporaryDirectory(prefix="nvalt-r2-ux-") as temporary:
    root=Path(temporary)
    harness=root/"probe.m"; harness.write_text(code)
    binary=root/"probe"
    subprocess.run(["xcrun","clang","-arch","x86_64","-mmacosx-version-min=10.13","-fno-objc-arc","-fblocks",
        "-Wno-deprecated-declarations","-I",str(REPO/"Sources/Application"),"-framework","Cocoa",str(harness),"-o",str(binary)],check=True)
    imports=subprocess.check_output(["nm","-u",str(binary)],text=True)
    for forbidden in ("_OBJC_CLASS_$_NSApplication","_OBJC_CLASS_$_NSWorkspace","_OBJC_CLASS_$_NSUserDefaults","_SecKeychain"):
        assert forbidden not in imports,forbidden
    for flavor,configuration,name,identifier,notes,scheme in (
        ("development","Development","nvALT Development","net.elasticthreads.nv.development","Notational Data Development","nvalt-dev"),
        ("release","ForBuilding","nvALT","net.elasticthreads.nv","Notational Data","nvalt")):
        built=REPO/"build/DerivedData/Build/Products"/configuration/(name+".app")
        metadata=plistlib.loads((built/"Contents/Info.plist").read_bytes())
        assert metadata["CFBundleName"]==metadata["CFBundleExecutable"]==name
        assert metadata["CFBundleIdentifier"]==identifier and metadata["NVBuildFlavor"]==flavor
        assert scheme in [value for item in metadata["CFBundleURLTypes"] for value in item["CFBundleURLSchemes"]]
        readme=(REPO/"README.markdown").read_text()
        for documented in (name+".app",identifier,notes,scheme+"://"):
            assert "`"+documented+"`" in readme,documented
        app=root/(flavor+".app")/"Contents"
        (app/"MacOS").mkdir(parents=True); shutil.copy2(binary,app/"MacOS/probe")
        metadata.update(CFBundleExecutable="probe",CFBundleIdentifier="org.nvalt.round2.ux."+flavor)
        (app/"Info.plist").write_bytes(plistlib.dumps(metadata))
        record=json.loads(subprocess.check_output([str(app/"MacOS/probe"),flavor],text=True))
        records.append(record)
        print(f"PASS: {flavor}: {record['checks']} real-escaping and local-routing checks")
launch='open "build/DerivedData/Build/Products/Development/nvALT Development.app"'
for path in ("README.markdown","AGENTS.md"):
    assert launch in (REPO/path).read_text()
assert 'directoryName = NVIsDevelopmentBuild() ? @"Notational Data Development" : @"Notational Data";' in (REPO/"Sources/Storage/NotationFileManager.m").read_text()
assert "Development adds an `nvALT Development` subfolder inside a custom backup destination" in (REPO/"README.markdown").read_text()
assert "Development also adds an `nvALT Development` subfolder inside a custom backup root" in (REPO/"architecture.md").read_text()
result={"revision":frozen,"architecture":"x86_64","runtime":records,
    "documentation":"App names, preference domains, note-folder names, schemes, and quoted launch commands match current built metadata and documented identities.",
    "backup_limit":"Both documents describe the intended Development subfolder. This review does not assert first-use creation; Ousterhout owns that defect.",
    "harness_sha256":hashlib.sha256(code.encode()).hexdigest()}
(HERE/"results.json").write_text(json.dumps(result,indent=2)+"\n")
print("PASS: current installation documentation checks; custom-backup creation explicitly outside this probe")
