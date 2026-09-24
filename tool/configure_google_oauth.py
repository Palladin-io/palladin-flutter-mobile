"""Prepare ignored Google OAuth build inputs from explicit environment values."""
import argparse
import json
import os
from pathlib import Path
import re


def configure(root, flavor, platform, environ):
    names = ['GOOGLE_SERVER_CLIENT_ID']
    if platform == 'ios':
        names.append('GOOGLE_IOS_CLIENT_ID')
    values = {}
    for name in names:
        value = environ.get(name, '').strip()
        if not re.fullmatch(r'[0-9]+-[a-z0-9]+\.apps\.googleusercontent\.com', value):
            raise ValueError(f'Missing or invalid {name}')
        values[name] = value
    output = root / 'config' / f'google-oauth-{flavor}.local.json'
    output.parent.mkdir(exist_ok=True)
    output.write_text(json.dumps(values, indent=2) + '\n')
    if platform == 'ios':
        client = values['GOOGLE_IOS_CLIENT_ID']
        settings = {
            'GOOGLE_IOS_CLIENT_ID': client,
            'GOOGLE_REVERSED_CLIENT_ID': '.'.join(reversed(client.split('.'))),
            'GOOGLE_SERVER_CLIENT_ID': values['GOOGLE_SERVER_CLIENT_ID'],
        }
        target = root / 'ios' / 'Flutter' / 'flavors' / f'{flavor}.oauth.local.xcconfig'
        target.write_text(''.join(f'{key} = {value}\n' for key, value in settings.items()))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--flavor', choices=['local', 'staging', 'production'], required=True)
    parser.add_argument('--platform', choices=['android', 'ios'], required=True)
    args = parser.parse_args()
    try:
        configure(Path(__file__).resolve().parents[1], args.flavor, args.platform, os.environ)
    except ValueError as error:
        parser.exit(1, f'{error}\n')
