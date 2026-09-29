import importlib.util
import json
from pathlib import Path
import plistlib
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('firebase', Path(__file__).parents[1] / 'configure_firebase.py')
firebase = importlib.util.module_from_spec(spec)
spec.loader.exec_module(firebase)


class FirebaseConfigurationTest(unittest.TestCase):
    def test_android_preserves_multiclient_file_and_existing_oauth(self):
        content = json.dumps({
            'project_info': {'project_id': 'example-project'},
            'client': [{
                'client_info': {'android_client_info': {'package_name': package}},
                'oauth_client': [{'client_id': 'example-existing-client', 'client_type': 3}],
            } for package in ['io.palladin.mobile', 'io.palladin.mobile.staging']],
        }).encode()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for flavor in ['production', 'staging']:
                target = firebase.configure(root, flavor, 'android', content)
                self.assertEqual(target.read_bytes(), content)

    def test_ios_preserves_oauth_and_distribution_project(self):
        content = plistlib.dumps({
            'PROJECT_ID': 'example-existing-project', 'GOOGLE_APP_ID': 'example-ios-app',
            'BUNDLE_ID': 'io.palladin.mobile', 'CLIENT_ID': 'example-existing-client',
            'REVERSED_CLIENT_ID': 'example-existing-callback',
        })
        with tempfile.TemporaryDirectory() as directory:
            target = firebase.configure(Path(directory), 'production', 'ios', content)
            self.assertEqual(target.read_bytes(), content)

    def test_wrong_distribution_invalid_or_server_config_never_overwrites(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = root / 'ios/config/production/GoogleService-Info.plist'
            target.parent.mkdir(parents=True)
            target.write_bytes(b'existing')
            for platform, content in [
                ('android', b''), ('android', b'{}'),
                ('android', b'{"type":"service_account","private_key":"example"}'),
                ('ios', b'not a plist'),
                ('ios', plistlib.dumps({'BUNDLE_ID': 'io.palladin.mobile.staging',
                                       'GOOGLE_APP_ID': 'example', 'PROJECT_ID': 'example'})),
            ]:
                with self.subTest(platform=platform, content=content):
                    with self.assertRaises(ValueError):
                        firebase.configure(root, 'production', platform, content)
                    self.assertEqual(target.read_bytes(), b'existing')


if __name__ == '__main__':
    unittest.main()
