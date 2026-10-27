import pathlib
import runpy
import subprocess
import sys
import unittest
from unittest.mock import patch


class ResponseReadinessTests(unittest.TestCase):
    def test_invalid_scheme_waits_for_rejection_callback(self):
        for mode in ('web-http', 'web-missing'):
            with self.subTest(mode=mode):
                reads = []

                def output(command, **kwargs):
                    if command[3:5] == ['shell', 'cat']:
                        reads.append(True)
                        status = 'responseRejected=true' if len(reads) >= 2 else 'Synthetic encrypted cache ready'
                        return f'<hierarchy><node text="{status}"/></hierarchy>'
                    return ''

                script = pathlib.Path(__file__).resolve().parents[1] / 'exercise.py'
                with patch.object(sys, 'argv', ['exercise.py', '--serial', 'emulator-5554', '--mode', mode, '--inspect-response']), patch.object(subprocess, 'check_output', side_effect=output), patch('time.sleep'):
                    runpy.run_path(str(script), run_name='__main__')
                self.assertEqual(len(reads), 2)
