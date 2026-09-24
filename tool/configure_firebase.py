"""Install explicit Firebase client configuration without changing OAuth metadata."""
import argparse
import json
import os
from pathlib import Path
import plistlib


def configure(root, flavor, platform, content):
    bundle = 'io.palladin.mobile' + ('' if flavor == 'production' else f'.{flavor}')
    try:
        if platform == 'android':
            config = json.loads(content)
            clients = config['client']
            matches = [client for client in clients
                       if client['client_info']['android_client_info']['package_name'] == bundle]
            if len(matches) != 1 or not config['project_info']['project_id']:
                raise ValueError()
            target = root / 'android' / 'app' / 'src' / flavor / 'google-services.json'
        else:
            config = plistlib.loads(content)
            if config['BUNDLE_ID'] != bundle or not config['GOOGLE_APP_ID'] or not config['PROJECT_ID']:
                raise ValueError()
            target = root / 'ios' / 'config' / flavor / 'GoogleService-Info.plist'
        if 'private_key' in config or 'client_secret' in config:
            raise ValueError()
    except (ValueError, KeyError, TypeError, plistlib.InvalidFileException) as error:
        raise ValueError('Expected Firebase client configuration matching the distribution flavor') from error
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(content)
    return target


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--flavor', choices=['local', 'staging', 'production'], required=True)
    parser.add_argument('--platform', choices=['android', 'ios'], required=True)
    parser.add_argument('--source', type=Path, help='Downloaded client file; otherwise reads FIREBASE_CLIENT_CONFIG')
    args = parser.parse_args()
    try:
        content = args.source.read_bytes() if args.source else os.environ.get('FIREBASE_CLIENT_CONFIG', '').encode()
        configure(Path(__file__).resolve().parents[1], args.flavor, args.platform, content)
    except (OSError, ValueError) as error:
        parser.exit(1, 'Missing or invalid Firebase client configuration for this distribution\n')
