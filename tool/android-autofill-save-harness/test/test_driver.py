import importlib.util
from pathlib import Path
import subprocess
import unittest

spec = importlib.util.spec_from_file_location('save_exercise', Path(__file__).parents[1] / 'exercise.py')
exercise = importlib.util.module_from_spec(spec)
spec.loader.exec_module(exercise)


class HierarchyReadTests(unittest.TestCase):
    def test_unavailable_root_does_not_abort_wait_or_reuse_stale_xml(self):
        files = {'hierarchy': '<hierarchy><node text="stale"/></hierarchy>'}
        ready = False

        def android(*parts):
            if parts[:3] == ('shell', 'rm', '-f'):
                files.clear()
                return ''
            if parts[:3] == ('shell', 'uiautomator', 'dump'):
                self.assertEqual(parts[3], '--windows')
                if ready:
                    files['hierarchy'] = '<displays><display><hierarchy><node text="saveColdStartEmpty=true"/></hierarchy></display></displays>'
                return ''
            if parts[:3] == ('shell', 'test', '-s'):
                if not files:
                    raise subprocess.CalledProcessError(1, parts)
                return ''
            if parts[:2] == ('shell', 'cat'):
                if not files:
                    raise subprocess.CalledProcessError(1, parts)
                return files['hierarchy']
            raise AssertionError('Unexpected Android operation')

        self.assertEqual(exercise.read_nodes(android), [])
        self.assertEqual(files, {})
        ready = True
        self.assertEqual([node.get('text') for node in exercise.read_nodes(android)], ['saveColdStartEmpty=true'])
        self.assertEqual(files, {})

    def test_transport_failure_is_not_a_successful_empty_ui(self):
        def android(*parts):
            if parts[:3] == ('shell', 'uiautomator', 'dump'):
                raise subprocess.TimeoutExpired(parts, 15)
            return ''
        with self.assertRaises(subprocess.TimeoutExpired):
            exercise.read_nodes(android)


class FailureMetadataTests(unittest.TestCase):
    def test_diagnostics_reduce_device_output_to_known_booleans(self):
        def android(*parts):
            if parts[:4] == ('shell', 'dumpsys', 'activity', 'activities'):
                return 'mResumedActivity: synthetic-token ' + exercise.PROVIDER + '/io.palladin.mobile.MainActivity'
            if parts[:3] == ('shell', 'ps', '-A'):
                return 'NAME\n' + exercise.PROVIDER + '\n'
            return 'result=REJECTED package-value-must-not-escape'
        self.assertEqual(exercise.failure_state(android), {
            'providerProcessPresent': True, 'formProcessPresent': False,
            'providerResumed': True, 'formResumed': False, 'serviceCallbackObserved': True,
        })
