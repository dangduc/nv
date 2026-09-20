import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

import desktop_test_support as desktop


class DesktopRunnerTests(unittest.TestCase):
    def test_inventory_excludes_regular_apps_and_command_wrappers(self):
        root = str(Path(tempfile.gettempdir()).resolve())
        output = ('11 /Applications/nvALT Development.app/Contents/MacOS/nvALT Development\n'
                  '12 /Users/me/dev/nv/build/nvALT Development.app/Contents/MacOS/nvALT Development\n'
                  f'13 {root}/nvalt-window-tests-ab/Window Tests.app/Contents/MacOS/nvALT Development -ShowDockIcon YES\n'
                  f'14 /bin/sh -c {root}/nvalt-window-tests-ab/Window Tests.app/Contents/MacOS/nvALT Development\n')
        with patch.object(desktop.subprocess, 'check_output', return_value=output):
            self.assertEqual([pid for pid, _ in desktop.test_app_processes()], [13])

    def test_leftover_blocks_new_runs(self):
        with patch.object(desktop, 'test_app_processes', return_value=[(42, '/tmp/nvalt-test/Test.app/Contents/MacOS/test')]):
            with self.assertRaisesRegex(SystemExit, 'PID 42'):
                desktop.require_clean_desktop()

    def test_clean_desktop_is_allowed(self):
        with patch.object(desktop, 'test_app_processes', return_value=[]):
            desktop.require_clean_desktop()

    def test_normal_process_returns_exit_code(self):
        self.assertEqual(desktop.run_desktop_process([sys.executable, '-c', 'raise SystemExit(7)'], timeout=5), 7)

    def test_timeout_kills_a_process_that_ignores_term(self):
        with tempfile.TemporaryDirectory() as root:
            ready = Path(root) / 'ready'
            script = ('import os, signal, time; from pathlib import Path; '
                      'signal.signal(signal.SIGTERM, signal.SIG_IGN); '
                      f'Path({str(ready)!r}).write_text(str(os.getpid())); time.sleep(60)')
            with self.assertRaises(subprocess.TimeoutExpired):
                desktop.run_desktop_process([sys.executable, '-c', script], timeout=1)
            pid = int(ready.read_text())
            with self.assertRaises(ProcessLookupError):
                os.kill(pid, 0)

    def test_unreapable_process_has_only_bounded_waits(self):
        process = Mock()
        process.poll.return_value = None
        process.wait.side_effect = subprocess.TimeoutExpired('probe', 2)
        desktop._stop(process, None)
        self.assertEqual(process.send_signal.call_args_list,
                         [unittest.mock.call(signal.SIGTERM), unittest.mock.call(signal.SIGKILL)])
        self.assertEqual(process.wait.call_count, 2)
        for call in process.wait.call_args_list:
            self.assertEqual(call.kwargs, {'timeout': 2})

    def test_launch_services_cleanup_targets_only_this_app(self):
        binary = Path('/tmp/nvalt-ui/Test.app/Contents/MacOS/Test')
        processes = [(100, str(binary) + ' -arg'), (200, '/tmp/nvalt-peer/Peer.app/Contents/MacOS/Peer')]
        process = Mock()
        process.poll.return_value = 0
        with patch.object(desktop, 'test_app_processes', side_effect=[processes, [], []]), patch.object(desktop.os, 'kill') as kill:
            desktop._stop(process, binary)
        self.assertEqual(kill.call_args_list,
                         [unittest.mock.call(100, signal.SIGTERM)])


if __name__ == '__main__':
    unittest.main()
