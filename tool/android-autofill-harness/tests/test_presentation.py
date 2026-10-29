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

    def test_failed_marker_keeps_synthetic_failure_evidence_and_still_fails(self):
        def output(command, **kwargs):
            if 'uiautomator' in command:
                return 'UI hierarchy dumped'
            if 'cat' in command:
                return b'<hierarchy><node text="Synthetic unexpected screen"/></hierarchy>'
            return b'synthetic-png'

        with patch.object(sys, 'argv', ['presentation.py', '--serial', 'emulator-5554']), patch.object(subprocess, 'run'), patch.object(subprocess, 'check_output', side_effect=output), patch('time.sleep'), patch.object(pathlib.Path, 'write_bytes') as capture:
            with self.assertRaisesRegex(RuntimeError, 'Presentation assertions failed'):
                runpy.run_path(str(SCRIPT), run_name='__main__')
        self.assertEqual(capture.call_count, 2)
        self.assertIn(b'synthetic-png', [call.args[0] for call in capture.call_args_list])

    def test_one_launcher_overlay_is_recorded_then_real_assertions_still_required(self):
        self.launcher_case(repeat=False)

    def test_second_launcher_overlay_remains_failure(self):
        self.launcher_case(repeat=True)

    def test_transient_second_launcher_overlay_is_terminal(self):
        self.launcher_case(repeat='transient')

    def test_other_anr_dialogs_are_never_dismissed(self):
        for title in ("Palladin isn't responding", "System UI isn't responding", "Other isn't responding"):
            with self.subTest(title=title):
                self.launcher_case(repeat=False, title=title)

    def launcher_case(self, repeat, title="Pixel Launcher isn't responding"):
        state = {'closed': 0, 'language': '', 'night': '', 'dialogReads': 0}
        def run(command, **kwargs):
            if 'start' in command:
                state['language'] = command[command.index('language') + 1]
                state['night'] = command[command.index('night') + 1]
            if 'tap' in command:
                self.assertEqual(command[-2:], ['50', '50'])
                state['closed'] += 1
        def output(command, **kwargs):
            if 'uiautomator' in command:
                return 'UI hierarchy dumped'
            if 'cat' in command:
                if not state['closed'] or (repeat and (repeat is True or state['dialogReads'] < 2)):
                    state['dialogReads'] += 1
                    return f'''<hierarchy><node text="{title}" package="android"/><node text="Close app" package="android" class="android.widget.Button" enabled="true" bounds="[0,0][100,100]"/></hierarchy>'''.encode()
                return f'<hierarchy><node text="presentationVerified=true {state["language"]} night={state["night"]}"/></hierarchy>'.encode()
            return b'synthetic-launcher-overlay'
        with patch.object(sys, 'argv', ['presentation.py', '--serial', 'emulator-5554']), patch.object(subprocess, 'run', side_effect=run), patch.object(subprocess, 'check_output', side_effect=output), patch('time.sleep'), patch.object(pathlib.Path, 'write_bytes') as capture, patch.object(pathlib.Path, 'write_text') as metadata:
            if repeat or title != "Pixel Launcher isn't responding":
                with self.assertRaisesRegex(RuntimeError, 'Presentation assertions failed'):
                    runpy.run_path(str(SCRIPT), run_name='__main__')
            else:
                runpy.run_path(str(SCRIPT), run_name='__main__')
            self.assertEqual(state['closed'], 1 if title == "Pixel Launcher isn't responding" else 0)
            self.assertIn(b'synthetic-launcher-overlay', [call.args[0] for call in capture.call_args_list])
            self.assertEqual(any('"dismissedLauncherAnr": true' in call.args[0] for call in metadata.call_args_list), title == "Pixel Launcher isn't responding")
