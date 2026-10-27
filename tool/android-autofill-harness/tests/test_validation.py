import contextlib
import io
from pathlib import Path
import runpy
import subprocess
import sys
import unittest
from unittest.mock import patch


class ValidationPreparationTests(unittest.TestCase):
    def test_enrollment_failure_preserves_previews_without_seeding_cache(self):
        harness = Path(__file__).resolve().parents[1]
        events = []

        def output(command, **kwargs):
            if 'presentation.py' in ' '.join(map(str, command)):
                events.append('presentations')
                return 'presentationVerified=true\n'
            if command[:3] == ('git', 'rev-parse', 'HEAD'):
                return 'synthetic-commit'
            if command[:3] == ('git', 'status', '--porcelain'):
                return ''
            if 'io.palladin.autofill.harness.provider/io.palladin.mobile.MainActivity' in command:
                events.append('cache-seed')
            return 'null'

        def run(command, **kwargs):
            if 'prepare_ci.py' in ' '.join(map(str, command)):
                events.append('enrollment')
                raise subprocess.CalledProcessError(1, command)

        with patch.object(sys, 'argv', ['validate.py', '--serial', 'emulator-5554', '--prepare-ci']), \
                patch('subprocess.check_output', side_effect=output), \
                patch('subprocess.run', side_effect=run), \
                patch.object(Path, 'read_bytes', return_value=b'synthetic-apk'), \
                contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            try:
                runpy.run_path(str(harness / 'validate.py'), run_name='__main__')
            except (SystemExit, subprocess.CalledProcessError):
                pass
        self.assertEqual(events, ['presentations', 'enrollment'])
