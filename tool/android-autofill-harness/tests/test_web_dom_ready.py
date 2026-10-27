import pathlib
import runpy
import subprocess
import sys
import unittest
from unittest.mock import patch


class WebDomReadinessTests(unittest.TestCase):
    def test_negative_manual_request_waits_for_current_dom(self):
        state = {'reads': 0, 'requested': False}
        package = 'io.palladin.autofill.harness.form'
        service = 'io.palladin.autofill.harness.provider/io.palladin.mobile.autofill.PalladinAutofillService'

        def output(command, **kwargs):
            parts = command[3:]
            if parts[:2] == ['shell', 'cat']:
                state['reads'] += 1
                ready = str(state['reads'] >= 4).lower()
                requested = str(state['requested']).lower()
                return f'<hierarchy><node package="{package}" text="Request Autofill" enabled="true" bounds="[0,0][20,20]"/><node package="{package}" text="Verify fill" enabled="true" bounds="[0,30][20,50]"/><node package="{package}" text="requestIssued={requested} unavailable=true uiShown=false enabled=true domReady={ready} focusVerified=true unavailableEvents=1 shownEvents=0"/><node package="{package}" text="fieldsUnchanged=true"/></hierarchy>'
            if parts[:3] == ['shell', 'input', 'tap'] and parts[4] == '10':
                self.assertGreaterEqual(state['reads'], 4, 'Manual request preceded DOM readiness')
                state['requested'] = True
            if parts[:2] == ['shell', 'dumpsys']:
                return 'result=REJECTED'
            if parts[:3] == ['shell', 'settings', 'get']:
                return service
            return ''

        script = pathlib.Path(__file__).resolve().parents[1] / 'exercise.py'
        with patch.object(sys, 'argv', ['exercise.py', '--serial', 'emulator-5554', '--mode', 'web-search', '--expected', 'REJECTED']), patch.object(subprocess, 'check_output', side_effect=output), patch('time.sleep'):
            runpy.run_path(str(script), run_name='__main__')
        self.assertTrue(state['requested'])
