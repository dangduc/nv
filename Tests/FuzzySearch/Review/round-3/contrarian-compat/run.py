#!/usr/bin/env python3
"""Compare current Exact behavior with the complete pre-PR browser session."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
sys.path.insert(0, str(ROOT / "Tests"))
from compiler_support import include_flags

BASE = "a9539cca76e260546310caa4918d018f802b064b"
PRODUCTION = "11f571f"


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sanitize", action="store_true")
    parser.add_argument("--negative-control", action="store_true")
    args = parser.parse_args()
    out = ROOT / "build/FuzzySearchReview/round-3/contrarian-compat" / ("sanitize" if args.sanitize else "native")
    snapshot = out / "source-snapshot"
    out.mkdir(parents=True, exist_ok=True)
    tracked = subprocess.check_output(["git", "ls-files", "Sources", "Config", "ThirdParty/fzf-native"],
                                      cwd=ROOT, text=True).splitlines()
    for name in tracked:
        destination = snapshot / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / name, destination)
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    legacy = {}
    for suffix in ("h", "m"):
        path = f"Sources/Browser/NVBrowserSession.{suffix}"
        original = subprocess.check_output(["git", "show", f"{BASE}:{path}"], cwd=ROOT)
        adapted = original.replace(b"NVBrowserSession", b"LegacyExactSession")
        (out / f"LegacyExactSession.{suffix}").write_bytes(adapted)
        legacy[path] = {"original_sha256": sha(original), "renamed_sha256": sha(adapted)}
    fixture_path = ROOT / "Tests/FuzzySearch/Browser/browser-tests.m"
    fixture = fixture_path.read_text()
    prefix = fixture[:fixture.index("// Run the exact production occurrence-selection methods")]
    helpers = fixture[fixture.index("static BOOL Spin("):fixture.index("int main(void)")]
    probe = out / "probe.m"
    probe.write_text(prefix + helpers + (HERE / "cases.m").read_text())
    flags = ["-arch", "arm64", "-mmacosx-version-min=11.0", "-g", "-O1" if args.sanitize else "-O2",
             "-DUTF8PROC_STATIC", "-I" + str(out), "-I" + str(snapshot / "ThirdParty/fzf-native"),
             *include_flags(snapshot), *include_flags(ROOT)]
    if args.sanitize:
        flags += ["-fsanitize=address,undefined", "-fno-omit-frame-pointer"]
    production = ["Sources/Search/NVFZF.c", "ThirdParty/fzf-native/fzf.c",
                  "ThirdParty/fzf-native/utf8proc-2.10.0/utf8proc.c", "Sources/Search/NVSearchQuery.m",
                  "Sources/Search/NVSearchCorpus.m", "Sources/Search/NVSearchService.m",
                  "Sources/Browser/NVBrowserSession.m"]
    sources = [snapshot / name for name in production] + [out / "LegacyExactSession.m", probe]
    binary = out / "probe"

    def build():
        objects = []
        log = []
        for index, source in enumerate(sources):
            obj = out / f"{index}.o"
            language = ["-fblocks", "-fno-objc-arc", "-Wno-deprecated-declarations", "-Wno-incomplete-implementation",
                        "-Wno-protocol", "-Wno-incompatible-pointer-types", "-Wno-objc-method-access",
                        "-include", str(snapshot / "Config/Notation_Prefix.pch")] if source.suffix == ".m" else ["-std=c11"]
            result = subprocess.run(["xcrun", "clang", *flags, *language, "-c", str(source), "-o", str(obj)],
                                    cwd=ROOT, text=True, capture_output=True, timeout=60)
            log.append(result.stdout + result.stderr)
            (out / "compile.log").write_text("".join(log))
            result.check_returncode()
            objects.append(str(obj))
        result = subprocess.run(["xcrun", "clang", *flags, *objects, "-framework", "Cocoa", "-framework", "Carbon", "-o", str(binary)],
                                cwd=ROOT, text=True, capture_output=True, timeout=60)
        log.append(result.stdout + result.stderr)
        (out / "compile.log").write_text("".join(log))
        result.check_returncode()

    def run():
        env = dict(os.environ)
        env["UBSAN_OPTIONS"] = "halt_on_error=1"
        return subprocess.run([str(binary)], cwd=ROOT, text=True, capture_output=True, env=env, timeout=45)

    build()
    result = run()
    print(result.stdout, end="")
    print(result.stderr, end="")
    (out / "output.log").write_text(result.stdout + result.stderr)
    inputs = production + ["Sources/Browser/NVBrowserSession.h", "Sources/Search/NVSearchQuery.h",
                          "Sources/Search/NVSearchCorpus.h", "Sources/Search/NVSearchService.h",
                          "Sources/Model/NoteObject.h", "Sources/Preferences/GlobalPrefs.h", "Config/Notation_Prefix.pch"]
    record = {"command": sys.argv, "head_at_capture": head, "production_revision": PRODUCTION, "legacy_revision": BASE,
              "exit_code": result.returncode, "stdout": result.stdout, "stderr": result.stderr, "architecture": "arm64",
              "source_snapshot": str(snapshot.relative_to(ROOT)), "legacy_sources": legacy,
              "production_sha256": {name: sha((snapshot / name).read_bytes()) for name in inputs},
              "matches_production_revision": {name: (snapshot / name).read_bytes() == subprocess.check_output(
                  ["git", "show", f"{PRODUCTION}:{name}"], cwd=ROOT) for name in inputs},
              "fixture_sha256": {str(path.relative_to(ROOT)): sha(path.read_bytes()) for path in [fixture_path, HERE / "cases.m", HERE / "run.py"]},
              "assembled_probe_sha256": sha(probe.read_bytes()), "negative_control": None}
    result.check_returncode()
    if args.negative_control:
        path = snapshot / "Sources/Browser/NVBrowserSession.m"
        original = path.read_text()
        old = '@" :\\t\\r\\n"'
        assert original.count(old) == 1, "Expected one current Exact separator definition"
        try:
            path.write_text(original.replace(old, '@" \\t\\r\\n"'))
            build()
            rejected = run()
            log = rejected.stdout + rejected.stderr
            (out / "omit-colon.log").write_text(log)
            assert rejected.returncode != 0 and "legacy Exact ordered results match" in log, log
            record["negative_control"] = {"name": "omit-colon-separator", "exit_code": rejected.returncode, "output": log}
            print("PASS: removing the current colon separator fails the legacy Exact oracle")
        finally:
            path.write_text(original)
            build()
    (HERE / ("sanitize-results.json" if args.sanitize else "native-results.json")).write_text(json.dumps(record, indent=2) + "\n")


if __name__ == "__main__":
    main()
