"""Validate signing metadata without emitting certificates or profile contents."""
import argparse
import datetime
import hashlib
import plistlib
from pathlib import Path


def validate_profiles(app, extension, team_id, bundle_id, now, certificate_fingerprints, app_group):
    for profile, identifier in [(app,bundle_id),(extension,bundle_id+'.CredentialProvider')]:
        expiry=profile['ExpirationDate']
        if expiry.tzinfo is None: expiry=expiry.replace(tzinfo=datetime.timezone.utc)
        if expiry <= now: raise ValueError('Provisioning profile expired')
        if profile.get('TeamIdentifier') != [team_id]: raise ValueError('Profile team mismatch')
        if 'ProvisionedDevices' in profile or profile.get('ProvisionsAllDevices'):
            raise ValueError('An App Store distribution profile is required')
        entitlements=profile['Entitlements']
        if entitlements.get('application-identifier') != f'{team_id}.{identifier}':
            raise ValueError('Profile app identifier mismatch')
        if entitlements.get('get-task-allow') is not False:
            raise ValueError('Debug entitlement is not allowed')
        if app_group not in entitlements.get('com.apple.security.application-groups',[]):
            raise ValueError('Required App Group is missing')
        if not entitlements.get('com.apple.developer.authentication-services.autofill-credential-provider'):
            raise ValueError('AutoFill entitlement is missing')
        if not any(hashlib.sha256(c).hexdigest() in certificate_fingerprints
                   for c in profile.get('DeveloperCertificates',[])):
            raise ValueError('Distribution certificate is absent from profile')
    if not app['Entitlements'].get('com.apple.developer.associated-domains'):
        raise ValueError('Associated Domains entitlement is missing')


def main():
    p=argparse.ArgumentParser()
    for name in ('app','extension','certificate'): p.add_argument('--'+name,type=Path,required=True)
    for name in ('team','bundle','app-group'): p.add_argument('--'+name,required=True)
    a=p.parse_args()
    validate_profiles(plistlib.loads(a.app.read_bytes()),plistlib.loads(a.extension.read_bytes()),
                      a.team,a.bundle,datetime.datetime.now(datetime.timezone.utc),
                      {hashlib.sha256(a.certificate.read_bytes()).hexdigest()},a.app_group)
    print('iOS signing profile metadata verified')

if __name__=='__main__':
    try: main()
    except (ValueError,KeyError,OSError) as error:
        raise SystemExit('iOS signing preflight failed; verify profile expiry, identifiers, certificate and entitlements') from None
