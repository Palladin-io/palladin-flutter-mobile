import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('oauth', Path(__file__).parents[1] / 'configure_google_oauth.py')
oauth = importlib.util.module_from_spec(spec)
spec.loader.exec_module(oauth)


class GoogleOAuthConfigurationTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        (self.root / 'ios/Flutter/flavors').mkdir(parents=True)
        self.values = {
            'GOOGLE_SERVER_CLIENT_ID': '123-testserver.apps.googleusercontent.com',
            'GOOGLE_IOS_CLIENT_ID': '456-testios.apps.googleusercontent.com',
        }

    def test_ios_uses_one_explicit_audience_and_matching_callback(self):
        oauth.configure(self.root, 'production', 'ios', self.values)
        config = json.loads((self.root / 'config/google-oauth-production.local.json').read_text())
        self.assertEqual(config, self.values)
        settings = (self.root / 'ios/Flutter/flavors/production.oauth.local.xcconfig').read_text()
        self.assertIn('GOOGLE_REVERSED_CLIENT_ID = com.googleusercontent.apps.456-testios\n', settings)
        self.assertIn('GOOGLE_SERVER_CLIENT_ID = ' + config['GOOGLE_SERVER_CLIENT_ID'] + '\n', settings)

    def test_android_does_not_require_an_ios_client(self):
        oauth.configure(self.root, 'staging', 'android', {'GOOGLE_SERVER_CLIENT_ID': self.values['GOOGLE_SERVER_CLIENT_ID']})
        config = json.loads((self.root / 'config/google-oauth-staging.local.json').read_text())
        self.assertEqual(set(config), {'GOOGLE_SERVER_CLIENT_ID'})

    def test_missing_or_injected_values_fail_before_writing(self):
        for key in self.values:
            for bad in ['', 'example', self.values[key] + '\nOTHER_SETTING = injected']:
                with self.subTest(key=key, bad=bad):
                    values = {**self.values, key: bad}
                    with self.assertRaises(ValueError):
                        oauth.configure(self.root, 'local', 'ios', values)
                    self.assertFalse((self.root / 'config').exists())
