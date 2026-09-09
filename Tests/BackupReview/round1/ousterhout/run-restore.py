#!/usr/bin/env python3
"""Execute the current application restore method with call-order collaborators."""
from pathlib import Path
import subprocess
import tempfile
ROOT = Path(__file__).resolve().parents[4]
source = (ROOT / "Sources/Application/NVApplicationController.m").read_text()
start = source.index("- (BOOL)restoreBackupArchive:")
end = source.index("- (IBAction)newWindow:", start)
method = source[start:end]
template = Path(__file__).with_name("restore-contract.m.in").read_text()
with tempfile.TemporaryDirectory(prefix="nv-review-restore-") as temporary:
    temp = Path(temporary)
    generated = temp / "restore.m"
    binary = temp / "restore-contract"
    generated.write_text(template.replace("// PRODUCTION_RESTORE_METHOD", method))
    command = ["xcrun", "clang", "-fno-objc-arc", "-Werror", "-Wno-deprecated-declarations", str(generated),
        "-framework", "Cocoa", "-framework", "Carbon", "-o", str(binary)]
    subprocess.run(command, check=True)
    subprocess.run([str(binary), temporary], check=True, timeout=30)
    mutations = {
        "skip-original-prepare": method.replace("if (![library prepareForBackupRestoreWithError:error]) return NO;", ""),
        "recommit-after-prepare": method.replace("restoring = YES;", "restoring = YES; for (AppController *browser in [self browserControllers]) [browser finishEditing];", 1),
        "skip-resume-on-failure": method.replace("[library resumeAfterBackupRestoreFailureWithError:&resumeError]", "YES"),
    }
    for name, changed in mutations.items():
        if method == changed:
            raise SystemExit(f"mutation did not apply: {name}")
        generated.write_text(template.replace("// PRODUCTION_RESTORE_METHOD", changed))
        subprocess.run(command, check=True)
        result = subprocess.run([str(binary), temporary], capture_output=True, text=True, timeout=30)
        if result.returncode == 0:
            raise SystemExit(f"unsafe mutation accepted: {name}")
        print(f"PASS: rejected {name}")
