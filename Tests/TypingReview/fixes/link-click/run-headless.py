#!/usr/bin/env python3
"""Exercise the exact production callback with controlled click flags and targets."""
from pathlib import Path
import subprocess

suite = Path(__file__).resolve().parent
repo = suite.parents[3]
out = suite / "generated"
out.mkdir(exist_ok=True)
source = (repo / "Sources/Editor/LinkingEditor.m").read_text()
callback = source[source.index("- (void)clickedOnLink:"):source.index("- (NSMenu *)menuForEvent:")]
(out / "click.inc").write_text(callback)
source = (repo / "Sources/Editor/NVSourceAnalysis.m").read_text()
freshness = source[source.index("static char NVSourceLinksCurrentKey;"):source.index("NSArray *NVSourceLinkRuns(")]
(out / "freshness.inc").write_text(freshness)
command = ["xcrun", "clang", "-arch", "x86_64", "-mmacosx-version-min=10.13",
                "-fno-objc-arc", "-Wno-deprecated-declarations", "-framework", "Cocoa",
                "-I", str(out), str(suite / "headless.m"), "-o", str(out / "headless")]
subprocess.run(command, check=True)
result = subprocess.run([str(out / "headless")], capture_output=True, text=True, timeout=15)
(suite / "headless-output.txt").write_text(result.stdout + result.stderr)
print(result.stdout, end="")
print(result.stderr, end="")
if result.returncode:
    raise SystemExit(result.returncode)
guard_end = callback.index("\tNSEvent *currentEvent")
signature_end = callback.index("{\n") + 2
mutations = {
    "old early return": callback[:signature_end] + "\tif (!NVSourceLinksAreCurrent([self textStorage])) return;\n" + callback[guard_end:],
    "unguarded stale target": callback[:signature_end] + callback[guard_end:],
}
messages = []
try:
    for label, mutated in mutations.items():
        (out / "click.inc").write_text(mutated)
        subprocess.run(command, check=True)
        negative = subprocess.run([str(out / "headless")], capture_output=True, text=True, timeout=15)
        if negative.returncode == 0 or "FAIL:" not in negative.stderr:
            raise SystemExit(f"Negative control did not fail as expected: {label}")
        messages.append(f"PASS: negative control rejects {label}")
finally:
    (out / "click.inc").write_text(callback)
(suite / "headless-output.txt").write_text(result.stdout + result.stderr + "\n".join(messages) + "\n")
print("\n".join(messages))
