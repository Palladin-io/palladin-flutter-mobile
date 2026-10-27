import pathlib
import runpy
import subprocess
import sys
import unittest
from unittest.mock import patch

SCRIPT = pathlib.Path(__file__).resolve().parents[1] / 'presentation.py'


class PresentationDriverChecks(unittest.TestCase):
    def test_null_root_waits_for_real_marker_without_reading_stale_xml(self):
        current = {}
        dumps = 0
        reads = 0

        def run(command, **kwargs):
            if 'start' in command:
                current['language'] = command[command.index('language') + 1]
                current['night'] = command[command.index('night') + 1]

        def output(command, **kwargs):
            nonlocal dumps, reads
            if 'uiautomator' in command:
                dumps += 1
                return 'ERROR: null root node returned by UiTestAutomationBridge.' if dumps == 1 else 'UI hierarchy dumped'
            if 'cat' in command:
                reads += 1
                return f'<hierarchy><node text="presentationVerified=true {current["language"]} night={current["night"]}"/></hierarchy>'
            return b'synthetic-png'

        with patch.object(sys, 'argv', ['presentation.py', '--serial', 'emulator-5554']), patch.object(subprocess, 'run', side_effect=run), patch.object(subprocess, 'check_output', side_effect=output), patch('time.sleep'), patch.object(pathlib.Path, 'write_bytes'):
            runpy.run_path(str(SCRIPT), run_name='__main__')
        self.assertEqual((dumps, reads), (5, 4))

    def test_transport_timeout_fails_without_transition_retry(self):
        with patch.object(sys, 'argv', ['presentation.py', '--serial', 'emulator-5554']), patch.object(subprocess, 'run'), patch.object(subprocess, 'check_output', side_effect=subprocess.TimeoutExpired('adb', 15)) as output, patch('time.sleep'):
            with self.assertRaises(subprocess.TimeoutExpired):
                runpy.run_path(str(SCRIPT), run_name='__main__')
        self.assertEqual(output.call_count, 1)
