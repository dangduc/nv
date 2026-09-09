#!/usr/bin/env python3
"""Compile isolated review checks against the production C bridge."""
import argparse
import hashlib
import json
import pathlib
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[4]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--intel-compile-only", action="store_true")
    args = parser.parse_args()
    mode = "intel-compile-only" if args.intel_compile_only else "arm64-sanitize"
    build = ROOT / "build/FuzzySearchReview/round-1/torvalds" / mode
    build.mkdir(parents=True, exist_ok=True)
    paths = sorted((ROOT / "Sources/Search").glob("*")) + sorted((ROOT / "ThirdParty/fzf-native").rglob("*"))
    metadata = {
        "head": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "branch": subprocess.check_output(["git", "branch", "--show-current"], cwd=ROOT, text=True).strip(),
        "sources": {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths if p.is_file()},
    }
    (HERE / (mode + "-sources.json")).write_text(json.dumps(metadata, indent=2) + "\n")
    log = (HERE / (mode + ".log")).open("w")

    def run(command):
        text = "+ " + " ".join(map(str, command)) + "\n"
        print(text, end="", flush=True)
        log.write(text); log.flush()
        process = subprocess.run(list(map(str, command)), cwd=ROOT, text=True, stdout=subprocess.PIPE,
                                 stderr=subprocess.STDOUT, timeout=120)
        print(process.stdout, end="", flush=True)
        log.write(process.stdout); log.flush()
        if process.returncode:
            raise SystemExit(process.returncode)

    run(["sw_vers"]); run(["xcodebuild", "-version"]); run(["clang", "--version"])
    core = ROOT / "Tests/FuzzySearch/Core"
    reference = build / "reference.c"
    reference.write_text('#include "NVFZF.h"\n#include "fzf.h"\n#include "fzf-private.h"\n'
                         '#include <stdlib.h>\n#include <string.h>\n#include <limits.h>\n'
                         'typedef void *emacs_value;\nstruct Str { const char *b; size_t len; };\n' +
                         (core / "UpstreamReference.inc").read_text() + "\n" +
                         (core / "reference_wrapper.inc").read_text())
    arch = ["-arch", "x86_64", "-mmacosx-version-min=10.13"] if args.intel_compile_only else [
        "-arch", "arm64", "-mmacosx-version-min=11.0", "-fsanitize=address,undefined", "-fno-omit-frame-pointer"]
    flags = ["clang", "-std=c11", "-O1", "-g", "-Wall", "-Wextra", "-Werror", "-Wno-unused-function",
             "-Wno-unused-parameter", "-Wno-sign-compare", "-DUTF8PROC_STATIC",
             "-I", ROOT / "Sources/Search", "-I", ROOT / "ThirdParty/fzf-native"] + arch
    sources = [ROOT / "Sources/Search/NVFZF.c", ROOT / "ThirdParty/fzf-native/fzf.c",
               ROOT / "ThirdParty/fzf-native/utf8proc-2.10.0/utf8proc.c", reference, HERE / "probe.c"]
    objects = []
    for i, path in enumerate(sources):
        obj = build / f"{i}.o"; run(flags + ["-c", path, "-o", obj]); objects.append(obj)
    executable = build / "review-probe"
    run(flags + objects + ["-o", executable])
    if not args.intel_compile_only:
        run([executable])
    else:
        print("PASS: Intel compile and link only. No Intel executable was launched.")
        log.write("PASS: Intel compile and link only. No Intel executable was launched.\n")
    log.close()


if __name__ == "__main__":
    main()
