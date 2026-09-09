#!/usr/bin/env python3
"""Measure native scoring and single-candidate cancellation without a desktop."""
from pathlib import Path
import argparse
import subprocess

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--cancel', action='store_true', help='Measure prepared 1/8 MiB candidate cancellation')
args = parser.parse_args()
out = ROOT / 'build/FuzzySearchCoreTests'
out.mkdir(parents=True, exist_ok=True)
source = HERE / ('cancellation-benchmark.c' if args.cancel else 'benchmark.c')
exe = out / ('cancellation-benchmark' if args.cancel else 'core-benchmark')
files = [source, ROOT / 'ThirdParty/fzf-native/fzf.c', ROOT / 'ThirdParty/fzf-native/utf8proc-2.10.0/utf8proc.c']
# The paired scratch experiment includes NVFZF.c to inspect its private slab.
if args.cancel:
    files.insert(1, ROOT / 'Sources/Search/NVFZF.c')
subprocess.run(['clang', '-std=c11', '-O2', '-g', '-DUTF8PROC_STATIC',
    '-I', str(ROOT/'Sources/Search'), '-I', str(ROOT/'ThirdParty/fzf-native'),
    *map(str, files), '-pthread', '-o', str(exe)], check=True, timeout=60)
subprocess.run([str(exe)], check=True, timeout=180)
