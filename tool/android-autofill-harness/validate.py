#!/usr/bin/env python3
"""Build and validate one clean committed checkout, recording its exact identity."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser()
parser.add_argument('--serial', required=True)
parser.add_argument('--gradle', default='gradle')
parser.add_argument('--prepare-ci', action='store_true', help='Enroll synthetic biometrics after visual checks on a fresh CI emulator')
args = parser.parse_args()
if not args.serial.startswith('emulator-'):
    raise RuntimeError('Validation is restricted to an explicitly selected emulator')
root = Path(__file__).resolve().parents[2]
harness = root / 'tool/android-autofill-harness'
adb = os.environ.get('ADB', 'adb')


def output(*command):
    return subprocess.check_output(command, cwd=root, text=True, timeout=45).strip()


def clean_commit():
    if output('git', 'status', '--porcelain'):
        raise RuntimeError('Commit all intended source changes before authoritative validation')
    return output('git', 'rev-parse', 'HEAD')


def android(*command):
    return output(adb, '-s', args.serial, *command)


commit = clean_commit()
subprocess.run([args.gradle, '-p', str(harness), 'clean', ':provider:testDebugUnitTest', ':form:testDebugUnitTest', 'assembleDebug'], cwd=root, check=True, timeout=600)
report = {'commit': commit, 'checkout': str(root), 'device': args.serial, 'apkSha256': {}, 'cases': []}
for module in ('provider', 'form'):
    apk = harness / module / f'build/outputs/apk/debug/{module}-debug.apk'
    report['apkSha256'][module] = hashlib.sha256(apk.read_bytes()).hexdigest()
    android('install', '-r', str(apk))
report['jvmTests'] = sum(int(ET.parse(path).getroot().get('tests')) for module in ('provider', 'form') for path in (harness / module / 'build/test-results/testDebugUnitTest').glob('TEST-*.xml'))
prior_provider = android('shell', 'settings', 'get', 'secure', 'autofill_service')
prior_keyboard = android('shell', 'settings', 'get', 'secure', 'show_ime_with_hard_keyboard')
prior_hidden_policy = android('shell', 'settings', 'get', 'global', 'hidden_api_policy')
if prior_hidden_policy not in ('null', '2'):
    raise RuntimeError('Restore the default hidden API policy before authoritative OS validation')
try:
    android('shell', 'settings', 'put', 'secure', 'autofill_service', 'io.palladin.autofill.harness.provider/io.palladin.mobile.autofill.PalladinAutofillService')
    android('shell', 'settings', 'put', 'secure', 'show_ime_with_hard_keyboard', '1')
    presentation = subprocess.check_output([sys.executable, '-u', str(harness / 'presentation.py'), '--serial', args.serial], cwd=root, text=True, timeout=240)
    print(presentation, end='', flush=True)
    report['presentations'] = presentation.strip().splitlines()
    if args.prepare_ci:
        subprocess.run([sys.executable, '-u', str(harness / 'prepare_ci.py'), '--serial', args.serial], cwd=root, check=True, timeout=240)
    android('shell', 'am', 'start', '-n', 'io.palladin.autofill.harness.provider/io.palladin.mobile.MainActivity')
    positive = ('native-login', 'native-username', 'web-login', 'web-username')
    negative = ('native-search', 'native-otp', 'native-confirm', 'native-hidden', 'native-disabled', 'native-container', 'web-search', 'web-otp', 'web-confirm', 'web-hidden', 'web-disabled', 'web-http')
    cases = [(mode, '--inspect-response') for mode in (*positive, 'web-empty', 'native-empty', 'web-http', 'web-missing')]
    cases += [(mode, '--inspect-response', '--inline-mode', inline_mode) for mode in positive for inline_mode in ('absent', 'unsupported')]
    cases += [(mode, '--inspect-response') for mode in (
        'native-username-manual', 'native-username-manual-verified',
        'native-username-manual-password', 'web-username-manual', 'native-username-manual-cancel')]
    cases += [(mode, '--fill') for mode in (*positive, 'native-username-hint',
        'native-login-opaque', 'native-username-manual', 'native-username-manual-verified')]
    cases += [(mode, '--expected', 'NO_RESPONSE' if mode == 'web-http' else 'REJECTED') for mode in negative]
    for case in cases:
        if android('shell', 'settings', 'get', 'global', 'hidden_api_policy') != prior_hidden_policy:
            raise RuntimeError('Synthetic response inspector did not restore hidden API policy')
        result = subprocess.check_output([sys.executable, '-u', str(harness / 'exercise.py'), '--serial', args.serial, '--mode', *case], cwd=root, text=True, timeout=180)
        print(result, end='', flush=True)
        report['cases'].append({'arguments': list(case), 'result': result.strip()})
    if clean_commit() != commit:
        raise RuntimeError('Source identity changed during validation')
    if android('shell', 'settings', 'get', 'global', 'hidden_api_policy') != prior_hidden_policy:
        raise RuntimeError('Hidden API policy changed during validation')
    destination = harness / 'build/validation.json'
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(report, indent=2) + '\n')
    print('Validated clean commit ' + commit, flush=True)
    print('Evidence: ' + str(destination), flush=True)
finally:
    for namespace, key, previous in [('secure', 'autofill_service', prior_provider), ('secure', 'show_ime_with_hard_keyboard', prior_keyboard), ('global', 'hidden_api_policy', prior_hidden_policy)]:
        if previous == 'null':
            android('shell', 'settings', 'delete', namespace, key)
        else:
            android('shell', 'settings', 'put', namespace, key, previous)
