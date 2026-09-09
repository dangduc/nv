#!/usr/bin/env python3
"""Round 2 preservation evidence with real archives and extracted capture methods."""
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
sys.path.insert(0, str(ROOT / "Tests"))
from compiler_support import include_flags

OUT = ROOT / "build/BackupReview/round2/contrarian_data"
OUT.mkdir(parents=True, exist_ok=True)
data_source = (ROOT / "Sources/Utilities/NSData_transformations.m").read_text()
methods = data_source[data_source.index("@implementation NSData (NVUtilities)"):
                      data_source.index("- (unsigned long)CRC32")]
(OUT / "data-methods.m").write_text(
    '#import "NSData_transformations.h"\n#include "pbkdf2.h"\n'
    '#include <zlib.h>\n#include <unistd.h>\n' + methods + "\n@end\n")
capture_source = (ROOT / "Sources/Storage/NotationController.m").read_text()
begin = capture_source.index("- (BOOL)flushAllNoteChanges {")
end = capture_source.index("- (BOOL)prepareForBackupRestoreWithError:", begin)
capture_methods = capture_source[begin:end]
(OUT / "main.m").write_text((HERE / "probe.m.in").read_text().replace(
    "// EXTRACTED_CAPTURE_METHODS", capture_methods))

objc_sources = [
    "Sources/Model/NoteObject.m", "Sources/Preferences/NotationPrefs.m",
    "Sources/Storage/FrozenNotation.m", "Sources/Storage/NVBackupArchive.m",
    "Sources/Storage/DiskUUIDEntry.m", "Sources/Model/LabelObject.m",
    "Tests/BackupArchive/native/support.m", "Tests/BackupArchive/native/aes-provider.m",
    OUT / "data-methods.m", OUT / "main.m",
]
c_sources = ["Sources/Utilities/BufferUtils.c", "ThirdParty/Crypto/pbkdf2.c",
             "ThirdParty/Crypto/hmacsha1.c"]
objects = []
for index, source in enumerate(objc_sources + c_sources):
    source = ROOT / source
    obj = OUT / f"part-{index}.o"
    command = ["xcrun", "clang", "-c", "-arch", "arm64", "-mmacosx-version-min=11.0",
               "-O1", "-Wno-deprecated-declarations", "-Wno-incomplete-implementation",
               *include_flags(ROOT)]
    if source.suffix == ".m" or source.name == "BufferUtils.c":
        command += ["-x", "objective-c", "-fno-objc-arc", "-include",
                    str(ROOT / "Config/Notation_Prefix.pch")]
    subprocess.run([*command, str(source), "-o", str(obj)], check=True, timeout=30)
    objects.append(str(obj))
binary = OUT / "capture-preservation"
subprocess.run(["xcrun", "clang", "-arch", "arm64", *objects, "-framework", "Cocoa",
                "-framework", "Carbon", "-framework", "Security", "-lz", "-o", str(binary)],
               check=True, timeout=30)
result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=90)
(OUT / "results.log").write_text(result.stdout + result.stderr)
print(result.stdout, end="")
print(result.stderr, end="", file=sys.stderr)
raise SystemExit(result.returncode)
