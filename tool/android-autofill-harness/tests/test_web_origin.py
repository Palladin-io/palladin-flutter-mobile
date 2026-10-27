import ast
import pathlib
import re
import unittest


class WebOriginGateTests(unittest.TestCase):
    def test_web_handoff_requires_reported_single_verified_domain(self):
        source = pathlib.Path(__file__).resolve().parents[1] / 'exercise.py'
        namespace = {'re': re}
        tree = ast.parse(source.read_text())
        exec(compile(ast.Module(body=[node for node in tree.body if isinstance(node, ast.FunctionDef)], type_ignores=[]), str(source), 'exec'), namespace)
        self.assertIn('assert_web_origin', namespace)
        gate = namespace['assert_web_origin']
        gate('domains=ONE\norigin=VERIFIED\n')
        for snapshot in ('domains=ZERO\norigin=VERIFIED\n', 'domains=AMBIGUOUS\norigin=VERIFIED\n', 'domains=ONE\norigin=UNVERIFIED\n', ''):
            with self.subTest(snapshot=snapshot), self.assertRaisesRegex(AssertionError, 'Web fixture did not report one verified domain'):
                gate(snapshot)
