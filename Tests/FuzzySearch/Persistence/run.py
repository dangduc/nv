#!/usr/bin/env python3
"""Run production persistence methods with in-memory model and defaults fixtures."""
from pathlib import Path
import argparse
import subprocess

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
OUT = ROOT / 'build/FuzzySearchPersistenceTests'


def section(path, first, last):
    source = (ROOT / path).read_text()
    start = source.index(first)
    return source[start:source.index(last, start)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sanitize', action='store_true')
    parser.add_argument('--arch', choices=['arm64', 'x86_64'])
    parser.add_argument('--compile-only', action='store_true')
    parser.add_argument('--mutation', choices=['drop-row', 'legacy-fuzzy'], help='Negative check: the suite must fail')
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    extracted = (
        section('Sources/Browser/BookmarksController.m', 'static NSString *BMSearchStringKey', '#define MovedBookmarksType') + '\n' +
        section('Sources/Browser/SavedSearchesController.m', 'static NSString *SSSearchStringKey', '#define MovedSearchesType') + '\n' +
        '@implementation GlobalPrefs\n' +
        section('Sources/Preferences/GlobalPrefs.m', '- (void)setLastSearchString:', '- (void)saveCurrentBookmarksFromSender:') +
        '@end\n@implementation TestDualField\n' +
        section('Sources/UI/DualField.m', '- (BOOL)hasFollowedLinks', '- (void)setSnapbackString:') +
        '@end\n')
    if args.mutation == 'drop-row':
        extracted = extracted.replace('if (resultRowKey) [value setObject:resultRowKey forKey:BMResultRowKey];', '')
    elif args.mutation == 'legacy-fuzzy':
        extracted = extracted.replace('? @"fuzzy" : @"exact") copy]', '? @"fuzzy" : @"fuzzy") copy]', 1)
    (OUT / 'production.inc').write_text(extracted)
    binary = OUT / ('persistence-' + (args.arch or 'native') + ('-sanitize' if args.sanitize else ''))
    command = ['clang', '-fno-objc-arc', '-fblocks', '-O1', '-g', '-Wall', '-Wextra', '-Werror',
               '-Wno-unused-parameter', '-Wno-objc-missing-super-calls', '-I', str(ROOT / 'Sources/Browser'), '-I', str(OUT),
               str(HERE / 'probe.m'), '-framework', 'Cocoa', '-o', str(binary)]
    if args.arch:
        command += ['-arch', args.arch, '-mmacosx-version-min=10.13' if args.arch == 'x86_64' else '-mmacosx-version-min=11.0']
    if args.sanitize:
        command += ['-fsanitize=address,undefined', '-fno-omit-frame-pointer']
    subprocess.run(command, check=True, timeout=60)
    if not args.compile_only:
        subprocess.run([str(binary)], check=True, timeout=30)


if __name__ == '__main__':
    main()
