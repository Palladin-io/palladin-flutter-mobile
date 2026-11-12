#!/usr/bin/env python3
"""Assert installed-target visibility from the debug provider UID, without values."""
import argparse
import json
import re
import subprocess


def visible(adb, serial, provider, target):
    command = [adb, '-s', serial, 'shell']
    if provider:
        command += ['run-as', provider, '/system/bin/cmd', 'package']
    else:
        command += ['pm']
    result = subprocess.run(command + ['path', '--user', '0', target],
                            capture_output=True, text=True, timeout=10)
    if result.returncode not in (0, 1) or result.stderr.strip():
        raise RuntimeError('Package visibility probe could not execute')
    return result.returncode == 0 and result.stdout.startswith('package:')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--adb', required=True)
    parser.add_argument('--serial', required=True)
    parser.add_argument('--provider', required=True)
    parser.add_argument('--target', required=True)
    args = parser.parse_args()
    for value in (args.provider, args.target):
        if not re.fullmatch(r'[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+', value):
            parser.error('Invalid package identifier')
    installed = visible(args.adb, args.serial, None, args.target)
    own_visible = visible(args.adb, args.serial, args.provider, args.provider)
    target_visible = visible(args.adb, args.serial, args.provider, args.target)
    print(json.dumps({'installed': installed, 'provider_uid_control': own_visible,
                      'target_visible_to_provider': target_visible}))
    if not installed or not own_visible:
        raise SystemExit('INVALID_PROBE: target missing or run-as control failed')
    if not target_visible:
        raise SystemExit('FAIL: installed target hidden from provider UID')


if __name__ == '__main__':
    main()
