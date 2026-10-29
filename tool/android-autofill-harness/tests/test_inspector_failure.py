import ast
import json
import pathlib
import subprocess
import unittest
from unittest.mock import Mock, MagicMock


class InspectorFailureTests(unittest.TestCase):
    def setUp(self):
        source = pathlib.Path(__file__).resolve().parents[1] / 'exercise.py'
        self.namespace = {'json': json, 'provider': 'synthetic.provider', 'command': Mock()}
        functions = [node for node in ast.parse(source.read_text()).body if isinstance(node, ast.FunctionDef)]
        exec(compile(ast.Module(body=functions, type_ignores=[]), str(source), 'exec'), self.namespace)
        self.namespace['command'] = Mock()

    def test_failed_transport_does_not_replace_original_failure(self):
        self.namespace['command'].side_effect = subprocess.TimeoutExpired('adb', 15)
        destination = MagicMock()
        self.namespace['collect_inspector_failure'](destination)
        destination.__truediv__.assert_not_called()

    def test_collects_only_bounded_harness_files(self):
        self.namespace['command'].side_effect = [json.dumps({'phases': ['RESULT_STARTED']}), '', '[{"reason":4,"status":1}]']
        destination = MagicMock()
        self.namespace['collect_inspector_failure'](destination)
        encoded = destination.__truediv__.return_value.write_text.call_args.args[0]
        self.assertEqual(json.loads(encoded), {'inspector': {'phases': ['RESULT_STARTED']}, 'exits': [{'reason': 4, 'status': 1}]})
        commands = self.namespace['command'].call_args_list
        self.assertIn('run-as', commands[0].args)
        self.assertIn('collectDiagnostics', commands[1].args)

    def test_oversized_file_is_not_exported(self):
        self.namespace['command'].side_effect = ['x' * 16385, '', '[]']
        destination = MagicMock()
        self.namespace['collect_inspector_failure'](destination)
        encoded = destination.__truediv__.return_value.write_text.call_args.args[0]
        self.assertEqual(json.loads(encoded), {'exits': []})
