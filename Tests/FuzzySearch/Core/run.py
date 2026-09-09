#!/usr/bin/env python3
"""Compare the bridge with pinned upstream native scoring and sorting.

Only generated code, objects, and executables are written below build/. The
checked reference retains upstream GPL-3.0-or-later code without importing
the Emacs runtime. No application is built or launched by this runner.
"""

import argparse
import hashlib
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
HERE = pathlib.Path(__file__).resolve().parent
REVISION = "4b9236e8cd1e9f9f3aaf5f2ebf83f1fc5995d38d"


def run(args):
    print("+", " ".join(str(item) for item in args), flush=True)
    subprocess.run([str(item) for item in args], check=True, cwd=ROOT, timeout=180)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--upstream", type=pathlib.Path,
                        default=ROOT / "ThirdParty/fzf-native")
    parser.add_argument("--sanitize", action="store_true",
                        help="Enable AddressSanitizer and UndefinedBehaviorSanitizer")
    parser.add_argument("--arch", choices=["arm64", "x86_64"], help="Target architecture (default: host)")
    parser.add_argument("--compile-only", action="store_true", help="Compile and link without running")
    parser.add_argument("--mutation", choices=["ignore-scorer-oom"], help="Negative check: the suite must fail")
    args = parser.parse_args()
    upstream = args.upstream.resolve()
    import json
    manifest = json.loads((upstream / "upstream.json").read_text())
    if manifest["revision"] != REVISION:
        raise SystemExit("Unexpected vendored revision")
    for name, digest in manifest["files"].items():
        if hashlib.sha256((upstream / name).read_bytes()).hexdigest() != digest:
            raise SystemExit(f"Vendored source changed without a provenance update: {name}")
    extracted = (HERE / "UpstreamReference.inc").read_text()
    output = ROOT / "build/FuzzySearchCoreTests" / (("sanitize" if args.sanitize else "native") + ("-" + args.arch if args.arch else ""))
    output.mkdir(parents=True, exist_ok=True)
    reference = output / "upstream_reference.c"
    reference.write_text(
        "/* SPDX-License-Identifier: GPL-3.0-or-later */\n"
        f"/* Mechanically extracted from dangduc/fzf-native {REVISION}. */\n"
        '#include "NVFZF.h"\n#include "fzf.h"\n#include "fzf-private.h"\n'
        '#include <stdlib.h>\n#include <string.h>\n#include <limits.h>\n'
        "typedef void *emacs_value;\nstruct Str { const char *b; size_t len; };\n"
        + extracted + "\n" + (HERE / "reference_wrapper.inc").read_text())
    print(f"Upstream reference SHA-256: {hashlib.sha256(extracted.encode()).hexdigest()}")
    common = ["clang", "-std=c11", "-O1" if args.sanitize else "-O2", "-g",
              "-Wall", "-Wextra", "-Werror", "-Wno-unused-function", "-DUTF8PROC_STATIC",
              "-I", ROOT / "Sources/Search", "-I", upstream]
    if args.arch:
        common += ["-arch", args.arch, "-mmacosx-version-min=10.13" if args.arch == "x86_64" else "-mmacosx-version-min=11.0"]
    if args.sanitize:
        common += ["-fsanitize=address,undefined", "-fno-omit-frame-pointer"]
    bridge = ROOT / "Sources/Search/NVFZF.c"
    if args.mutation:
        source = bridge.read_text()
        guard = "if (fzf_allocation_failed()) return job->status = NVFZF_OUT_OF_MEMORY;"
        if source.count(guard) != 1:
            raise SystemExit("Cannot locate the exact scorer OOM guard for mutation")
        bridge = output / "NVFZF-mutated.c"
        bridge.write_text(source.replace(guard, "/* negative mutation: ignore upstream scorer OOM */"))
    files = [(bridge, "bridge", ["-include", HERE / "allocator_hooks.h"]),
             (upstream / "fzf.c", "fzf", ["-include", HERE / "matcher_allocator_hooks.h", "-Wno-unused-parameter", "-Wno-sign-compare"]),
             (upstream / "utf8proc-2.10.0/utf8proc.c", "utf8proc", []),
             (reference, "reference", []), (HERE / "probe.c", "probe", [])]
    objects = []
    for path, name, flags in files:
        obj = output / f"{name}.o"
        run(common + flags + ["-c", path, "-o", obj])
        objects.append(obj)
    executable = output / "nvfzf-core-tests"
    run(common + objects + ["-pthread", "-o", executable])
    if not args.compile_only:
        run([executable])


if __name__ == "__main__":
    try:
        main()
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
