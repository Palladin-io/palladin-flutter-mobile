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

    def check(self, diagnosis='No services match', status='requestIssued=true unavailable=true uiShown=false enabled=true', selected='provider/service', unchanged=True):
        nodes = [ET.Element('node', {'package': 'fixture', 'text': status}), ET.Element('node', {'package': 'fixture', 'text': 'fieldsUnchanged=' + str(unchanged).lower()})]
        self.assertTrue('negative_outcome' in self.namespace, 'Negative outcome must require current fixture evidence')
        return self.namespace['negative_outcome'](diagnosis, nodes, selected)

    def test_unbound_service_needs_fresh_unavailable_callback_and_untouched_fields(self):
        self.assertEqual(self.check(), 'SYSTEM_UNAVAILABLE')
        self.assertEqual(self.check(diagnosis='result=REJECTED', status='requestIssued=true unavailable=false uiShown=false enabled=true'), 'REJECTED')
        for overrides in ({'status': 'requestIssued=true unavailable=false uiShown=false enabled=true'}, {'status': 'requestIssued=false unavailable=true uiShown=false enabled=true'}, {'status': 'requestIssued=true unavailable=true uiShown=true enabled=true'}, {'selected': 'other/service'}, {'unchanged': False}, {'diagnosis': 'result=RESPONSE_OFFERED'}):
            with self.subTest(overrides=overrides), self.assertRaises(AssertionError):
                self.check(**overrides)
