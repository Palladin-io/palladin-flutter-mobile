import copy
import datetime
import hashlib
import sys
import unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from verify_ios_profiles import validate_profiles

class ProfileTest(unittest.TestCase):
    def setUp(self):
        self.now=datetime.datetime(2026,1,1,tzinfo=datetime.timezone.utc)
        self.app={'ExpirationDate':datetime.datetime(2027,1,1),'TeamIdentifier':['TEAM'],
                  'DeveloperCertificates':[b'cert'],'Entitlements':{
                  'application-identifier':'TEAM.io.palladin.mobile','get-task-allow':False,
                  'com.apple.developer.associated-domains':['*'],
                  'com.apple.security.application-groups':['group.io.palladin.mobile'],
                  'com.apple.developer.authentication-services.autofill-credential-provider':True}}
        self.extension=copy.deepcopy(self.app)
        self.extension['Entitlements']['application-identifier']='TEAM.io.palladin.mobile.CredentialProvider'

    def validate(self):
        validate_profiles(self.app,self.extension,'TEAM','io.palladin.mobile',self.now,
                          {hashlib.sha256(b'cert').hexdigest()},'group.io.palladin.mobile')

    def test_valid_distribution_pair(self): self.validate()
    def test_rejects_missing_entitlement(self):
        del self.app['Entitlements']['com.apple.developer.associated-domains']
        with self.assertRaises(ValueError): self.validate()
    def test_rejects_expiry(self):
        self.extension['ExpirationDate']=datetime.datetime(2025,1,1)
        with self.assertRaises(ValueError): self.validate()
    def test_rejects_wrong_id(self):
        self.app['Entitlements']['application-identifier']='TEAM.io.other'
        with self.assertRaises(ValueError): self.validate()
    def test_rejects_certificate_mismatch(self):
        self.app['DeveloperCertificates']=[b'other']
        with self.assertRaises(ValueError): self.validate()
    def test_rejects_development_or_adhoc(self):
        self.app['ProvisionedDevices']=['device']
        with self.assertRaises(ValueError): self.validate()
    def test_rejects_wrong_group(self):
        self.extension['Entitlements']['com.apple.security.application-groups']=['group.other']
        with self.assertRaises(ValueError): self.validate()
