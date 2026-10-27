import ast
import pathlib
import re
import unittest


class FrameworkSnapshotTests(unittest.TestCase):
    def test_only_bounded_framework_state_is_retained(self):
        source = pathlib.Path(__file__).resolve().parents[1] / 'exercise.py'
        namespace = {'re': re}
        tree = ast.parse(source.read_text())
        exec(compile(ast.Module(body=[node for node in tree.body if isinstance(node, ast.FunctionDef)], type_ignores=[]), str(source), 'exec'), namespace)
        snapshot = namespace['framework_snapshot']('''
 state: STATE_ACTIVE
 mResponses: 1
 mDestroyed: false
 mShowingSaveUi: false
 mHasCallback: true
 mViewStates size: 2
 fieldValues=[never-retain-this-value]
 state: untrusted-value
 mResponses: 1 secret
 mDestroyed: false secret
 mSelectedDatasetIds: private-identifier
''')
        self.assertEqual(snapshot, {'state': ['STATE_ACTIVE'], 'mResponses': ['1'], 'mDestroyed': ['false'], 'mShowingSaveUi': ['false'], 'mHasCallback': ['true'], 'mViewStates size': ['2']})
        self.assertEqual(len(namespace['framework_snapshot']('state: STATE_ACTIVE\n' * 100)['state']), 8)
