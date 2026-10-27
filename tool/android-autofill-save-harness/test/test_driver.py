import importlib.util
from pathlib import Path
import subprocess
import unittest
import xml.etree.ElementTree as ET

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


class LabelMatchTests(unittest.TestCase):
    def test_flutter_labels_and_native_text_match_exactly(self):
        for attribute in ('content-desc', 'text'):
            node = ET.Element('node', {attribute: 'Arm save', 'enabled': 'true'})
            self.assertTrue(exercise.matches_label(node, 'Arm save'))
            self.assertFalse(exercise.matches_label(node, 'save'))
            node.set('enabled', 'false')
            self.assertFalse(exercise.matches_label(node, 'Arm save'))


class HierarchyMetadataTests(unittest.TestCase):
    def test_arbitrary_labels_and_roles_never_escape(self):
        nodes = [ET.Element('node', {
            'text': 'arbitrary-private-text', 'content-desc': 'saveColdStartEmpty=true',
            'class': 'android.view.View', 'bounds': '[1,2][30,40]', 'enabled': 'true',
        }), ET.Element('node', {
            'text': 'another-private-value', 'class': 'private-role', 'bounds': 'bad',
        })]
        result = exercise.hierarchy_metadata(nodes)
        self.assertEqual(result, [
            {'role': 'android.view.View', 'bounds': [1, 2, 30, 40], 'enabled': True,
             'coldStartEmpty': True, 'coldStartNotEmpty': False, 'armButton': False,
             'harnessInitial': False},
            {'role': 'other', 'bounds': None, 'enabled': False,
             'coldStartEmpty': False, 'coldStartNotEmpty': False, 'armButton': False,
             'harnessInitial': False},
        ])


class LauncherAnrTests(unittest.TestCase):
    def dialog(self, title="Pixel Launcher isn't responding"):
        return [ET.Element('node', {'text': title, 'package': 'android'}),
                ET.Element('node', {'text': 'Close app', 'package': 'android',
                           'class': 'android.widget.Button', 'enabled': 'true',
                           'bounds': '[70,898][1010,1024]'})]

    def test_only_exact_launcher_system_dialog_can_be_dismissed(self):
        nodes = self.dialog()
        self.assertIs(exercise.launcher_anr_close(nodes), nodes[1])
        for title in ("Palladin isn't responding", "System UI isn't responding", "Other isn't responding"):
            self.assertIsNone(exercise.launcher_anr_close(self.dialog(title)))
        self.assertIsNone(exercise.launcher_anr_close(nodes + [nodes[1]]))
        self.assertIsNone(exercise.launcher_anr_close(nodes + self.dialog("Other isn't responding")))
        nodes[1].set('package', exercise.PROVIDER)
        self.assertIsNone(exercise.launcher_anr_close(nodes))
        for attribute, value in (('enabled', 'false'), ('bounds', ''), ('class', 'android.view.View')):
            invalid = self.dialog()
            invalid[1].set(attribute, value)
            self.assertIsNone(exercise.launcher_anr_close(invalid))
