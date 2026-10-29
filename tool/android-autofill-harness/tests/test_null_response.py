import importlib.util
from pathlib import Path
import unittest


class NullResponseTests(unittest.TestCase):
    def setUp(self):
        path = Path(__file__).resolve().parents[1] / 'null_response.py'
        spec = importlib.util.spec_from_file_location('null_response', path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        self.parse = module.password_null_response
        self.dump = '''  1 sessions:
    #1
      id: 123
      state: STATE_ACTIVE
      mComponentName: ComponentInfo{fixture/fixture.FormActivity}
      mStartTime: 1100
      mSessionLogs: 2
        #0: req=51, log=CAT=907, TYPE=SUCCESS(10), PKG=fixture, SERVICE=provider, ORDINAL=1, FLAGS=4, NUM_DATASETS=-1
        #1: req=52, log=CAT=907, TYPE=SUCCESS(10), PKG=fixture, SERVICE=provider, ORDINAL=2, FLAGS=133, NUM_DATASETS=-1
      mResponses: null
      mDestroyed: false
'''

    def check(self, dump=None, **changes):
        args = dict(api=35, started_ms=1000, form='fixture', provider='provider')
        args.update(changes)
        return self.parse(self.dump if dump is None else dump, **args)

    def test_current_manual_password_request_returned_null(self):
        self.assertTrue(self.check())

    def test_stale_other_session_and_platform_are_not_evidence(self):
        for changes in ({'started_ms': 1100}, {'started_ms': 1200}, {'started_ms': None}, {'form': 'other'}, {'provider': 'other'}, {'api': 34}):
            with self.subTest(changes=changes):
                self.assertFalse(self.check(**changes))
        self.assertFalse(self.check(self.dump + self.dump))
        self.assertFalse(self.check('No sessions'))

    def test_latest_request_must_be_successful_manual_password_null(self):
        for old, new in [('TYPE=SUCCESS(10)', 'TYPE=FAILURE(11)'), ('TYPE=SUCCESS(10)', 'TYPE=CLOSE(2)'), ('ORDINAL=2, FLAGS=133', 'ORDINAL=2, FLAGS=1'), ('ORDINAL=2, FLAGS=133', 'ORDINAL=2, FLAGS=4'), ('NUM_DATASETS=-1', 'NUM_DATASETS=0'), ('STATE_ACTIVE', 'STATE_FINISHED'), ('mDestroyed: false', 'mDestroyed: true'), ('mResponses: null', 'mResponses: 1'), ('mSessionLogs: 2', 'mSessionLogs: 3')]:
            with self.subTest(new=new):
                self.assertFalse(self.check(self.dump.replace(old, new)))
        latest = self.dump.replace('mSessionLogs: 2', 'mSessionLogs: 3').replace('      mResponses:', '        #2: req=53, log=CAT=907, TYPE=UNSUPPORTED(0), PKG=fixture, SERVICE=provider, ORDINAL=3, FLAGS=133\n      mResponses:')
        self.assertFalse(self.check(latest))

    def test_values_are_not_returned_or_used_as_status(self):
        self.assertIs(self.check(self.dump + 'password=private-value\n'), True)
        self.assertFalse(self.check('password=TYPE=SUCCESS(10), NUM_DATASETS=-1'))
        self.assertFalse(self.check(self.dump * 20000))

    def test_cross_session_fields_duplicate_ordinals_and_latest_other_source_fail(self):
        other = self.dump.replace('id: 123', 'id: 456').replace('ComponentInfo{fixture/', 'ComponentInfo{other/').replace('mStartTime: 1100', 'mStartTime: 1200')
        self.assertFalse(self.check(self.dump.replace('TYPE=SUCCESS(10)', 'TYPE=FAILURE(11)') + other))
        self.assertFalse(self.check(self.dump.replace('ORDINAL=2', 'ORDINAL=1')))
        self.assertFalse(self.check(self.dump.replace('ORDINAL=2, FLAGS=133', 'ORDINAL=2, FLAGS=133, AUTH_STATUS=AUTHENTICATED(1)')))
        self.assertFalse(self.check(self.dump.replace('SERVICE=provider, ORDINAL=2', 'SERVICE=other, ORDINAL=2')))

        self.assertFalse(self.check(self.dump.replace('PKG=fixture, SERVICE=provider, ORDINAL=2', 'PKG=other, SERVICE=provider, ORDINAL=2')))
        self.assertFalse(self.check(self.dump.replace('mStartTime: 1100', 'mStartTime: 1100\n      mStartTime: 1100')))
