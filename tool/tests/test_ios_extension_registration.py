import plistlib
import unittest
from pathlib import Path


class IOSCredentialProviderRegistrationTest(unittest.TestCase):
    def test_provider_uses_the_apple_registered_extension_point(self):
        # Apple NSExtensionPointIdentifier contract; a well-formed but unknown
        # identifier compiles and signs, then fails App Store validation.
        path = Path(__file__).resolve().parents[2] / 'ios/CredentialProvider/Info.plist'
        with path.open('rb') as source:
            extension = plistlib.load(source)['NSExtension']
        self.assertEqual(
            extension['NSExtensionPointIdentifier'],
            'com.apple.authentication-services-credential-provider-ui',
        )


if __name__ == '__main__':
    unittest.main()
