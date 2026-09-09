#!/usr/bin/env python3
"""Check extracted application ownership methods with recording collaborators."""
from pathlib import Path
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
application = (ROOT / "Sources/Application/NVApplicationController.m").read_text()


def extract(start, end):
    offset = application.index(start)
    return application[offset:application.index(end, offset)]


pieces = {
    "ATTACH": extract("- (void)setLibrary:(NotationController *)newLibrary {", "- (BOOL)restoreBackupArchive:"),
    "INVOKE": extract("- (void)performLibraryInvocation:", "- (void)preserveExternalContents:"),
    "TERMINATE": extract("- (void)applicationWillTerminate:", "- (IBAction)toggleNVActivation:"),
    "FORWARD": extract("- (id)forwardTargetForSelector:", "\n@end"),
}
template = (HERE / "ownership.m.in").read_text()


def materialize(replacements):
    result = template
    for name, source in replacements.items():
        result = result.replace("// PRODUCTION_" + name, source)
    return result


with tempfile.TemporaryDirectory(prefix="nvalt-r3-owner-") as directory:
    temporary = Path(directory)
    generated = temporary / "ownership.m"
    binary = temporary / "ownership"
    command = ["xcrun", "clang", "-fno-objc-arc", "-Wall", "-Wextra", "-Werror",
               "-Wno-unused-parameter", "-Wno-deprecated-declarations",
               "-framework", "Cocoa", str(generated), "-o", str(binary)]

    def run(source, capture=False):
        generated.write_text(source)
        subprocess.run(command, check=True, timeout=30)
        return subprocess.run([str(binary)], capture_output=capture, text=True, timeout=15)

    run(materialize(pieces)).check_returncode()
    mutations = {
        "prepared-session-recommit": ("ATTACH", "else [session closeWithoutCommitting];", "else [session close];"),
        "omit-closed-owner-attachment": ("ATTACH", "if (![browsers containsObject:initialBrowser]) [initialBrowser attachLibrary:library finishingOldLibrary:finish];", ""),
        "forget-origin-after-nested-call": ("INVOKE", "operationBrowser = previous;", "operationBrowser = nil; (void)previous;"),
        "leave-termination-permission-enabled": ("TERMINATE", "finishingTermination = NO;", "finishingTermination = YES;"),
    }
    for name, (piece, old, new) in mutations.items():
        changed = dict(pieces)
        if old not in changed[piece]:
            raise SystemExit(f"Mutation did not apply: {name}")
        changed[piece] = changed[piece].replace(old, new, 1)
        result = run(materialize(changed), capture=True)
        if result.returncode == 0:
            raise SystemExit(f"Unsafe mutation accepted: {name}")
        if "FAIL:" not in result.stderr:
            raise SystemExit(f"Mutation failed without an assertion: {name}\n{result.stderr}")
        print(f"PASS: rejected {name}: {result.stderr.strip()}")
