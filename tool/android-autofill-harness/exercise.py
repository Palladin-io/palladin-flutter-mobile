#!/usr/bin/env python3
"""Exercise installed synthetic APKs on an explicitly selected disposable emulator."""
import argparse
import json
from pathlib import Path
import os
import re
import subprocess
import time
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser()
parser.add_argument('--serial', required=True)
parser.add_argument('--mode', choices=['native-login', 'native-username', 'web-login', 'web-username', 'web-http', 'web-missing', 'web-empty', 'native-empty', 'web-search', 'web-otp', 'web-confirm', 'web-hidden', 'web-disabled', 'native-search', 'native-otp', 'native-confirm', 'native-hidden', 'native-disabled', 'native-container'], required=True)
parser.add_argument('--expected', choices=['RESPONSE_OFFERED', 'REJECTED', 'NO_RESPONSE'], default='RESPONSE_OFFERED')
parser.add_argument('--fill', action='store_true')
parser.add_argument('--inspect-response', action='store_true')
args = parser.parse_args()
if not args.serial.startswith('emulator-'):
    raise RuntimeError('This harness only operates on an emulator')
if not __debug__:
    raise RuntimeError('Run without Python optimization so every field assertion is checked')
adb = os.environ.get('ADB', 'adb')
form = 'io.palladin.autofill.harness.form'
provider = 'io.palladin.autofill.harness.provider'
service = provider + '/io.palladin.mobile.autofill.PalladinAutofillService'


def command(*parts):
    return subprocess.check_output([adb, '-s', args.serial, *parts], text=True, timeout=15, stderr=subprocess.STDOUT)


def nodes():
    try:
        status = command('shell', 'uiautomator', 'dump', '--windows', '/sdcard/palladin-synthetic-ui.xml')
        if status.strip() == 'ERROR: null root node returned by UiTestAutomationBridge.':
            return []
        raw = command('shell', 'cat', '/sdcard/palladin-synthetic-ui.xml')
        return list(ET.fromstring(raw).iter('node'))
    finally:
        command('shell', 'rm', '-f', '/sdcard/palladin-synthetic-ui.xml')


def tap_node(node):
    bounds = list(map(int, re.findall(r'\d+', node.get('bounds', ''))))
    if len(bounds) != 4:
        return False
    x1, y1, x2, y2 = bounds
    if x2 <= x1 or y2 <= y1 or node.get('enabled') == 'false':
        return False
    command('shell', 'input', 'tap', str((x1+x2)//2), str((y1+y2)//2))
    return True


def wait_for(predicate, message):
    for _ in range(6):
        if predicate(nodes()):
            return
        time.sleep(.3)
    raise AssertionError(message)


def tap_text(pattern):
    for _ in range(4):
        for node in nodes():
            if re.search(pattern, node.get('text', ''), re.I) and tap_node(node):
                return True
        time.sleep(.3)
    return False


def focus_field(required=True):
    # Native EditText and WebView's virtual input accessibility nodes share this
    # public class name. The source package prevents targeting system UI fields.
    for _ in range(6 if required else 1):
        for node in nodes():
            if (node.get('package') == form and
                    node.get('class') == 'android.widget.EditText' and tap_node(node)):
                return
        time.sleep(.3)
    if required:
        raise AssertionError('Synthetic focus field not exposed by accessibility')


def authenticate():
    wait_for(lambda tree: any(n.get('text') == 'Unlock Palladin' and
                             n.get('package') == 'com.android.systemui' for n in tree),
             'Real biometric prompt not shown')
    command('emu', 'finger', 'touch', '1')
    command('emu', 'finger', 'remove')
    if args.mode.startswith('native'):
        assert tap_text('Synthetic fixture'), 'Authenticated native picker missing'
        assert tap_text('Fill once'), 'Explicit manual warning missing'


def record_failure():
    if os.environ.get('GITHUB_ACTIONS') != 'true':
        return
    destination = Path(__file__).resolve().parent / 'build/exercise' / (
        args.mode + ('-response' if args.inspect_response else '-handoff'))
    destination.mkdir(parents=True, exist_ok=True)
    try:
        screenshot = subprocess.check_output(
            [adb, '-s', args.serial, 'exec-out', 'screencap', '-p'], timeout=15)
        (destination / 'screen.png').write_bytes(screenshot)
    except Exception:
        pass  # Diagnostic failure must not replace the original assertion.
    try:
        roles = {
            'Unlock Palladin to autofill': 'unlock-suggestion',
            'Unlock Palladin': 'biometric-title',
            'Synthetic fixture': 'synthetic-picker',
            'Fill once': 'manual-confirmation',
            'synthetic-user': 'synthetic-dataset',
            'Request Autofill': 'request-control',
            'Verify fill': 'verify-control',
            'fillVerified=true': 'fill-verified',
        }
        metadata = []
        for node in nodes()[:500]:
            item = {key: node.get(key) for key in (
                'package', 'class', 'resource-id', 'bounds', 'enabled', 'focused',
                'focusable', 'clickable', 'password')}
            item['role'] = roles.get(node.get('text'), 'other')
            metadata.append(item)
        (destination / 'nodes.json').write_text(json.dumps(metadata, indent=2) + '\n')
    except Exception:
        pass


try:
    command('shell', 'pm', 'set-app-links', '--package', form, '2' if args.mode.startswith('web') else '0', 'fixture.invalid')
    command('shell', 'am', 'force-stop', form)
    command('shell', 'am', 'force-stop', provider)
    if args.inspect_response:
        if args.mode not in ('native-login', 'native-username', 'web-login', 'web-username', 'web-http', 'web-missing', 'web-empty', 'native-empty'):
            raise RuntimeError('Response inspection uses the four credential fixtures')
        prior_policy = command('shell', 'settings', 'get', 'global', 'hidden_api_policy').strip()
        try:
            command('shell', 'settings', 'put', 'global', 'hidden_api_policy', '1')
            command('shell', 'am', 'start', '-n', provider + '/io.palladin.mobile.MainActivity', '--es', 'inspectResponse', args.mode)
            if args.mode in ('web-http', 'web-missing'):
                assert any(n.get('text') == 'responseRejected=true' for n in nodes()), 'Invalid scheme released a FillResponse'
                print(args.mode + ': no authentication result PASS')
            else:
                authenticate()
                expected_result = 'responseRejected=true' if args.mode.endswith('empty') else 'responseVerified=true'
                wait_for(lambda tree: any(n.get('text') == expected_result for n in tree),
                         'Actual FillResponse field ID/value assertions failed')
                print(args.mode + ': actual FillResponse dataset assertions PASS')
        finally:
            if prior_policy == 'null':
                command('shell', 'settings', 'delete', 'global', 'hidden_api_policy')
            else:
                command('shell', 'settings', 'put', 'global', 'hidden_api_policy', prior_policy)

    else:
        command('shell', 'am', 'start', '-n', form + '/io.palladin.autofill.form.FormActivity', '--es', 'mode', args.mode)
        positive = args.mode in ('native-login', 'native-username', 'web-login', 'web-username')
        focus_field(required=positive)
        if not positive:
            assert tap_text('Request Autofill'), 'Manual request control missing'
        diagnosis = ''
        for _ in range(30):
            diagnosis = command('shell', 'dumpsys', 'activity', 'service', service)
            if re.search(r'result=(RESPONSE_OFFERED|REJECTED)', diagnosis):
                break
            time.sleep(.1)
        if args.expected == 'NO_RESPONSE':
            if args.mode != 'web-http':
                raise RuntimeError('Only insecure WebView may be suppressed before the provider callback')
            assert 'result=RESPONSE_OFFERED' not in diagnosis, 'HTTP unexpectedly offered credentials'
            assert any(marker in diagnosis for marker in ('result=REJECTED', 'result=NO_REQUEST', 'No services match')), 'Unexpected HTTP provider state'
            outcome = 'REJECTED' if 'result=REJECTED' in diagnosis else 'FRAMEWORK_SUPPRESSED'
        else:
            assert 'result=' + args.expected in diagnosis, 'Unexpected provider outcome: ' + diagnosis
            outcome = args.expected
        print(args.mode + ': ' + outcome)
        if args.fill:
            assert args.expected == 'RESPONSE_OFFERED'
            if not tap_text('Unlock Palladin to autofill'):
                # The public fixture button issues AutofillManager.requestAutofill,
                # which can expose the dropdown when the IME ignores inline UI.
                assert tap_text('Request Autofill'), 'Manual request control missing'
                assert tap_text('Unlock Palladin to autofill'), 'Accessible unlock suggestion missing'
            authenticate()
            assert tap_text('^synthetic-user$'), 'Authenticated dataset missing'
            assert tap_text('Verify fill'), 'Fixture verification control missing'
            wait_for(lambda tree: any(n.get('text') == 'fillVerified=true' for n in tree),
                     'Synthetic field assertions failed')
            print(args.mode + ': biometric + selection + field assertions PASS')
except Exception:
    record_failure()
    raise
