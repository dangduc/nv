"""Prevent desktop probes from accumulating abandoned test apps."""
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time


def test_app_processes():
    """Return only copied nvALT apps below a disposable nvalt-* directory."""
    output = subprocess.check_output(
        ['ps', '-axo', 'pid=,command='], text=True, timeout=5)
    roots = {str(Path(tempfile.gettempdir()).resolve()), '/private/tmp', '/tmp'}
    found = []
    for line in output.splitlines():
        fields = line.strip().split(None, 1)
        if len(fields) != 2 or '.app/Contents/MacOS/' not in fields[1]:
            continue
        pid, command = fields
        path = str(Path(command.split('.app/Contents/MacOS/', 1)[0]).resolve())
        if any(path.startswith(root + '/nvalt-') for root in roots):
            found.append((int(pid), command))
    return found


def require_clean_desktop():
    leftovers = test_app_processes()
    if leftovers:
        details = '\n'.join(f'  PID {pid}: {command}' for pid, command in leftovers)
        raise SystemExit('Desktop tests stopped: a disposable test app is still running.\n'
                         + details + '\nClose it before retrying. If force-quit cannot remove it, '
                         'log out or restart before running more desktop tests.')


def _stop(process, app_binary):
    # Launch Services owns the actual app; terminating `open -W` alone leaves it open.
    for sig in (signal.SIGTERM, signal.SIGKILL):
        app_pids = []
        if app_binary is not None:
            binary = str(Path(app_binary).resolve())
            for pid, command in test_app_processes():
                command = str(Path(command).resolve())
                if command == binary or command.startswith(binary + ' '):
                    app_pids.append(pid)
        for pid in app_pids:
            try:
                os.kill(pid, sig)
            except ProcessLookupError:
                pass
        if process.poll() is None:
            process.send_signal(sig)
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            pass
        if app_pids:
            deadline = time.monotonic() + 2
            while time.monotonic() < deadline:
                remaining = {pid for pid, _ in test_app_processes()}
                if not remaining.intersection(app_pids):
                    break
                time.sleep(0.1)
    # Do not use an unbounded wait: a Rosetta task in kernel U state can survive SIGKILL.


def run_desktop_process(arguments, *, timeout, env=None, app_binary=None):
    process = subprocess.Popen(arguments, env=env)
    try:
        return process.wait(timeout=timeout)
    except (subprocess.TimeoutExpired, KeyboardInterrupt):
        _stop(process, app_binary)
        raise
