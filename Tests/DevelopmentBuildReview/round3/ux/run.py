#!/usr/bin/env python3
"""Check independent settings and browser restoration through disposable process histories."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile
import uuid

HERE=Path(__file__).resolve().parent
REPO=HERE.parents[3]
COMMIT="47d18f43cadb1a2eeeed9c7fbe379795c76faae7"
assert subprocess.check_output(["git","rev-parse","HEAD"],cwd=REPO,text=True).strip()==COMMIT
prefs=(REPO/"Sources/Preferences/GlobalPrefs.m").read_text()
application=(REPO/"Sources/Application/NVApplicationController.m").read_text()
def method(source,signature):
    start=source.index(signature);end=source.index("{",start)+1;depth=1
    while depth:
        depth+=(source[end]=="{")-(source[end]=="}");end+=1
    return source[start:end]
keys=["MakeURLsClickableKey","ShowWordCount","BackgroundTextColorKey","DarkBackgroundTextColorKey"]
constants="\n".join(re.search(r"^static NSString[^\n]*\b"+key+r"\s*=[^\n]+",prefs,re.M).group() for key in keys)
constants+="\n"+re.search(r"^static NSString[^\n]*NVBrowserWindowsKey[^\n]+",application,re.M).group()
for key in ("ShowWordCount","MakeURLsClickableKey"):
    assert re.search(r"\[NSNumber numberWithBool:YES\]\s*,\s*"+key,prefs)
signatures=["- (BOOL)showWordCount","- (void)setShowWordCount:","- (void)setMakeURLsClickable:","- (BOOL)URLsAreClickable",
    "- (void)setBackgroundTextColor:","- (NSColor*)backgroundTextColor","- (void)setDarkBackgroundTextColor:","- (NSColor*)darkBackgroundTextColor"]
source=(HERE/"probe.m").read_text().replace("@CONSTANTS@",constants).replace("@PREFERENCE_METHODS@","\n".join(method(prefs,s) for s in signatures))
source=source.replace("@WINDOW_METHODS@","\n".join(method(application,s) for s in ("- (void)saveWindowStates","- (void)restoreWindowStates")))
records=[];domains=[]
with tempfile.TemporaryDirectory(prefix="nvalt-r3-ux-") as temporary:
    root=Path(temporary)
    (root/"Home/Library/Preferences").mkdir(parents=True);(root/"Temp").mkdir()
    environment=dict(os.environ,CFFIXED_USER_HOME=str(root/"Home"),TMPDIR=str(root/"Temp")+"/")
    try:
        harness=root/"probe.m";harness.write_text(source);binary=root/"probe"
        subprocess.run(["xcrun","clang","-arch","x86_64","-mmacosx-version-min=10.13","-fno-objc-arc","-Wno-deprecated-declarations",
            "-I",str(REPO/"Sources/Application"),"-framework","Cocoa",str(harness),"-o",str(binary)],check=True)
        undefined=subprocess.check_output(["nm","-u",str(binary)],text=True)
        for forbidden in ("_OBJC_CLASS_$_NSApplication","_OBJC_CLASS_$_NSWorkspace","_SecKeychain"):
            assert forbidden not in undefined,forbidden
        apps={};run_id=uuid.uuid4().hex
        for flavor,configuration,name in (("development","Development","nvALT Development"),("release","ForBuilding","nvALT")):
            built=REPO/"build/DerivedData/Build/Products"/configuration/(name+".app")
            info=plistlib.loads((built/"Contents/Info.plist").read_bytes())
            assert info["NVBuildFlavor"]==flavor
            assert info["CFBundleIdentifier"]=="net.elasticthreads.nv"+(".development" if flavor=="development" else "")
            domain="org.nvalt.round3.ux."+run_id+"."+flavor;domains.append(domain)
            app=root/(flavor+".app")/"Contents";(app/"MacOS").mkdir(parents=True)
            shutil.copy2(binary,app/"MacOS/probe")
            info.update(CFBundleIdentifier=domain,CFBundleExecutable="probe")
            (app/"Info.plist").write_bytes(plistlib.dumps(info));apps[flavor]=app/"MacOS/probe"
        for flavor,phase in (("release","seed"),("development","seed"),("release","read"),("development","read"),
            ("development","update"),("release","read"),("development","read-updated"),("development","reset"),
            ("development","fresh"),("release","read")):
            run=subprocess.run([str(apps[flavor]),flavor,phase],env=environment,capture_output=True,text=True,timeout=30)
            if run.returncode: raise RuntimeError((flavor,phase,run.stdout,run.stderr))
            record=json.loads(run.stdout);records.append(record)
            print(f"PASS: {flavor} {phase}: {record['checks']} checks")
    finally:
        for domain in domains:
            assert domain.startswith("org.nvalt.round3.ux.")
            subprocess.run(["defaults","delete",domain],env=environment,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=10)
result={"revision":COMMIT,"architecture":"x86_64 under Rosetta","harness_sha256":hashlib.sha256(source.encode()).hexdigest(),
    "processes":len(records),"checks":sum(record["checks"] for record in records),"history":records,
    "limits":"Verbatim preference setters/getters and coordinator save/restore methods; browser state production/consumption and UI callbacks use recording collaborators."}
(HERE/"results.json").write_text(json.dumps(result,indent=2)+"\n")
