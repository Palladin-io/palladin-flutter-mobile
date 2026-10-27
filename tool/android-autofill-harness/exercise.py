#!/usr/bin/env python3
"""Exercise installed synthetic APKs on an explicitly selected disposable emulator."""
import argparse
import os
import re
import subprocess
import time
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser()
parser.add_argument('--serial', required=True)
parser.add_argument('--mode', choices=['native-login', 'native-username', 'web-login', 'web-username'], required=True)
parser.add_argument('--expected', choices=['RESPONSE_OFFERED', 'REJECTED'], default='RESPONSE_OFFERED')
parser.add_argument('--fill', action='store_true')
parser.add_argument('--inline-y', type=int, default=2050, help='Inline chip center on the test AVD (1344x2992 Pixel/Gboard)')
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
    return subprocess.check_output([adb, '-s', args.serial, *parts], text=True)


def nodes():
    command('shell', 'uiautomator', 'dump', '/sdcard/palladin-synthetic-ui.xml')
    raw = command('shell', 'cat', '/sdcard/palladin-synthetic-ui.xml')
    command('shell', 'rm', '/sdcard/palladin-synthetic-ui.xml')
    return list(ET.fromstring(raw).iter('node'))


def tap_text(pattern):
    for node in nodes():
        if re.search(pattern, node.get('text', ''), re.I):
            x1, y1, x2, y2 = map(int, re.findall(r'\d+', node.get('bounds')))
            command('shell', 'input', 'tap', str((x1+x2)//2), str((y1+y2)//2))
            return True
    return False


command('shell', 'pm', 'set-app-links', '--package', form, '1' if args.mode.startswith('web') else '0', 'fixture.invalid')
command('shell', 'am', 'force-stop', form)
command('shell', 'am', 'force-stop', provider)
command('shell', 'am', 'start', '-n', form + '/io.palladin.autofill.form.FormActivity', '--es', 'mode', args.mode)
time.sleep(2)
command('shell', 'input', 'tap', '200', '170')
diagnosis = ''
for _ in range(30):
    diagnosis = command('shell', 'dumpsys', 'activity', 'service', service)
    if re.search(r'result=(RESPONSE_OFFERED|REJECTED)', diagnosis):
        break
    time.sleep(.1)
assert 'result=' + args.expected in diagnosis, 'Unexpected provider outcome: ' + diagnosis
print(args.mode + ': ' + args.expected)
if args.fill:
    assert args.expected == 'RESPONSE_OFFERED'
    for _ in range(2):
        if tap_text('Unlock Palladin to autofill'):
            break
        time.sleep(.2)
    else:
        # Gboard's inline surface is absent from uiautomator's active-window XML
        # on the recorded API 37 AVD; retain its documented coordinate fallback.
        command('shell', 'input', 'tap', '670', str(args.inline_y))
    time.sleep(.5)
    assert any('Unlock Palladin' in n.get('text', '') for n in nodes()), 'Real biometric prompt not shown'
    command('emu', 'finger', 'touch', '1')
    time.sleep(.7)
    if args.mode.startswith('native'):
        assert tap_text('Synthetic fixture'), 'Authenticated native picker missing'
        assert tap_text('Fill once'), 'Explicit manual warning missing'
    assert tap_text('^synthetic-user$'), 'Authenticated dataset missing'
    assert tap_text('Verify fill'), 'Fixture verification control missing'
    assert any(n.get('text') == 'fillVerified=true' for n in nodes()), 'Synthetic field assertions failed'
    print(args.mode + ': biometric + selection + field assertions PASS')
