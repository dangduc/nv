#!/usr/bin/env python3
"""Check the current restore invocation boundary with native Objective-C forwarding."""
from pathlib import Path
import argparse
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
application = (ROOT / "Sources/Application/NVApplicationController.m").read_text()
session = (ROOT / "Sources/Browser/NVBrowserSession.m").read_text()
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--regress-return", action="store_true",
                    help="Remove return-buffer initialization in a temporary copy; the probe must reject it.")
args = parser.parse_args()


def extract(source, start, end):
    begin = source.index(start)
    return source[begin:source.index(end, begin)]


pieces = {
    "GUARD": extract(application, "- (BOOL)rejectInvocationDuringBackupRestore:(NSInvocation *)invocation {", "\n@end"),
    "PERFORM": extract(application, "- (void)performLibraryInvocation:", "- (void)preserveExternalContents:"),
    "TERMINATE": extract(application, "- (void)applicationWillTerminate:", "- (IBAction)toggleNVActivation:"),
    "FORWARD": extract(session, "- (BOOL)respondsToSelector:(SEL)selector", "\n@end"),
}
source = (HERE / "invocation-contract.m.in").read_text()
for name, implementation in pieces.items():
    marker = "// PRODUCTION_" + name
    assert source.count(marker) == 1
    source = source.replace(marker, implementation)
if args.regress_return:
    before = "        [invocation setReturnValue:[zero mutableBytes]];"
    assert source.count(before) == 1
    source = source.replace(before, "        (void)zero; // Deliberate review mutation: preserve the old return.")

with tempfile.TemporaryDirectory(prefix="nvalt-r3-invocation-") as directory:
    temporary = Path(directory)
    main = temporary / "probe.m"
    binary = temporary / "probe"
    main.write_text(source)
    command = ["xcrun", "clang", "-fno-objc-arc", "-Wall", "-Wextra", "-Werror",
               "-Wno-unused-parameter", "-framework", "Cocoa", str(main), "-o", str(binary)]
    print("Compile: " + " ".join(command), flush=True)
    subprocess.run(command, check=True, timeout=30)
    result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=30)
    print(result.stdout, end="")
    print(result.stderr, end="")
    if args.regress_return:
        assert result.returncode != 0, "The probe accepted the deliberately broken return contract"
        assert "FAIL: The full ABI return buffer is zero" in result.stderr
        print("PASS: the return-buffer mutation is rejected by the behavioral assertions")
    else:
        result.check_returncode()
