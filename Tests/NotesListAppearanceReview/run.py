#!/usr/bin/env python3
"""Run the notes list review probes serially and retain their output."""
import argparse
import os
from pathlib import Path
import signal
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--round', choices=['1', '2'])
    args = parser.parse_args()
    here = Path(__file__).resolve().parent
    root = here.parents[1]
    pattern = f'round{args.round}/*/run.py' if args.round else 'round[12]/*/run.py'
    runners = sorted(here.glob(pattern))
    expected = 5 if args.round else 10
    if len(runners) != expected:
        raise SystemExit(f'Expected {expected} review runners; found {len(runners)}')
    output = root / 'build/NotesListAppearanceReview/validation'
    output.mkdir(parents=True, exist_ok=True)
    failed = []
    for runner in runners:
        name = str(runner.parent.relative_to(here))
        log_path = output / (name.replace('/', '-') + '.log')
        print(f'Running {name}', flush=True)
        with log_path.open('w') as log:
            process = subprocess.Popen([sys.executable, str(runner)], cwd=root,
                                       stdout=log, stderr=subprocess.STDOUT,
                                       start_new_session=True)
            try:
                result = process.wait(timeout=120)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
                result = -1
        if result:
            failed.append(name)
            print(f'FAIL: {name}; see {log_path}', flush=True)
        else:
            print(f'PASS: {name}', flush=True)
    print(f'{len(runners) - len(failed)}/{len(runners)} review runners passed', flush=True)
    return bool(failed)


if __name__ == '__main__':
    sys.exit(main())
