import ast
import pathlib
import unittest
import xml.etree.ElementTree as ET


class NegativeOutcomeTests(unittest.TestCase):
    def setUp(self):
        source = pathlib.Path(__file__).resolve().parents[1] / 'exercise.py'
        self.namespace = {'form': 'fixture', 'provider': 'provider', 'service': 'provider/service'}
        tree = ast.parse(source.read_text())
        exec(compile(ast.Module(body=[node for node in tree.body if isinstance(node, ast.FunctionDef)], type_ignores=[]), str(source), 'exec'), self.namespace)

    def check(self, diagnosis='No services match', selected='provider/service', unchanged=True, auth=False, mode='native-search', **overrides):
        state = dict(requestIssued='true', unavailable='true', uiShown='false', enabled='true', domReady='true', focusVerified='true', unavailableEvents='1', shownEvents='0')
        target = overrides.pop('target', True)
        password_null = overrides.pop('password_null', False)
        state.update(overrides)
        nodes = [ET.Element('node', {'package': 'fixture', 'text': ' '.join(f'{key}={value}' for key, value in state.items())}), ET.Element('node', {'package': 'fixture', 'text': 'fieldsUnchanged=' + str(unchanged).lower()})]
        if mode == 'native-container' and target:
            nodes.append(ET.Element('node', {'package': 'fixture', 'class': 'android.widget.TextView', 'focused': 'true', 'text': 'Synthetic label'}))
        if auth:
            nodes.append(ET.Element('node', {'package': 'provider'}))
        return self.namespace['negative_outcome'](diagnosis, nodes, selected, mode, password_null=password_null)

    def test_current_callback_and_provider_rejection_remain_distinct(self):
        self.assertEqual(self.check(), 'SYSTEM_UNAVAILABLE')
        self.assertEqual(self.check(diagnosis='result=REJECTED', unavailable='false', unavailableEvents='0'), 'REJECTED')

    def test_web_no_callback_requires_complete_observable_evidence(self):
        self.assertEqual(self.check(mode='web-search', unavailable='false', unavailableEvents='0'), 'PLATFORM_NO_RESPONSE')
        self.assertEqual(self.check(mode='web-http', focusVerified='false', unavailable='false', unavailableEvents='0'), 'PLATFORM_NO_RESPONSE')
        for overrides in ({'domReady': 'false'}, {'focusVerified': 'false'}, {'enabled': 'false'}, {'requestIssued': 'false'}, {'uiShown': 'true'}, {'shownEvents': '1'}, {'selected': 'other/service'}, {'unchanged': False}, {'auth': True}, {'diagnosis': 'result=RESPONSE_OFFERED'}):
            with self.subTest(overrides=overrides), self.assertRaises(AssertionError):
                self.check(mode='web-search', unavailable='false', unavailableEvents='0', **overrides)
        with self.assertRaises(AssertionError):
            self.check(unavailable='false', unavailableEvents='0')

    def test_noneditable_container_no_callback_requires_exact_target_evidence(self):
        self.assertEqual(self.check(mode='native-container', unavailable='false', unavailableEvents='0', noneditableTarget='true'), 'PLATFORM_INELIGIBLE')
        for overrides in ({'noneditableTarget': 'false'}, {'target': False}, {'focusVerified': 'false'}, {'enabled': 'false'}, {'requestIssued': 'false'}, {'uiShown': 'true'}, {'shownEvents': '1'}, {'selected': 'other/service'}, {'unchanged': False}, {'auth': True}, {'diagnosis': 'result=RESPONSE_OFFERED'}):
            options = dict(noneditableTarget='true')
            options.update(overrides)
            with self.subTest(overrides=overrides), self.assertRaises(AssertionError):
                self.check(mode='native-container', unavailable='false', unavailableEvents='0', **options)

    def test_password_null_requires_framework_proof_and_existing_ui_guards(self):
        self.assertEqual(self.check(mode='native-otp', unavailable='false', unavailableEvents='0', password_null=True), 'SYSTEM_NULL_PASSWORD')
        for overrides in ({'password_null': False}, {'focusVerified': 'false'}, {'requestIssued': 'false'}, {'uiShown': 'true'}, {'shownEvents': '1'}, {'selected': 'other/service'}, {'unchanged': False}, {'auth': True}, {'diagnosis': 'result=RESPONSE_OFFERED'}):
            options = dict(password_null=True)
            options.update(overrides)
            with self.subTest(overrides=overrides), self.assertRaises(AssertionError):
                self.check(mode='native-otp', unavailable='false', unavailableEvents='0', **options)
