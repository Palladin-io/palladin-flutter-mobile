#!/usr/bin/env python3
"""Enroll one synthetic fingerprint through Settings on a disposable CI emulator."""
import argparse
import os
from pathlib import Path
import re
import subprocess
import time
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser()
parser.add_argument('--serial', required=True)
args = parser.parse_args()
if not args.serial.startswith('emulator-') or os.environ.get('GITHUB_ACTIONS') != 'true':
    raise RuntimeError('Enrollment is restricted to a disposable CI emulator')
adb = [os.environ.get('ADB', 'adb'), '-s', args.serial]
evidence = Path(__file__).resolve().parent / 'build/enrollment'
evidence.mkdir(parents=True, exist_ok=True)


def command(*parts):
    return subprocess.check_output(adb + list(parts), text=True, timeout=15)


def nodes():
    try:
        command('shell', 'uiautomator', 'dump', '/sdcard/palladin-enrollment-ui.xml')
        return list(ET.fromstring(command('shell', 'cat', '/sdcard/palladin-enrollment-ui.xml')).iter('node'))
    finally:
        command('shell', 'rm', '-f', '/sdcard/palladin-enrollment-ui.xml')


def tap(node):
    bounds = list(map(int, re.findall(r'\d+', node.get('bounds', ''))))
    if len(bounds) != 4 or node.get('enabled') == 'false':
        return False
    x1, y1, x2, y2 = bounds
    if x2 <= x1 or y2 <= y1:
        return False
    command('shell', 'input', 'tap', str((x1+x2)//2), str((y1+y2)//2))
    return True


if command('shell', 'getprop', 'ro.kernel.qemu').strip() != '1':
    raise RuntimeError('Target is not an Android emulator')
if command('shell', 'getprop', 'ro.build.version.sdk').strip() != '35':
    raise RuntimeError('Enrollment driver requires the official API 35 CI image')
# This public shell command succeeds only on the fresh, uncredentialed CI AVD.
# It cannot replace an existing PIN without the old credential.
result = command('shell', 'locksettings', 'set-pin', '246813')
if result.strip() != "Pin set to '246813'":
    raise RuntimeError('Fresh disposable emulator PIN setup failed')
command('shell', 'input', 'keyevent', 'KEYCODE_HOME')
command('shell', 'am', 'start', '-a', 'android.settings.FINGERPRINT_ENROLL')
pin_entered = False
touches = 0
deadline = time.monotonic() + 180
try:
    while time.monotonic() < deadline:
        tree = nodes()
        settings = [n for n in tree if n.get('package') == 'com.android.settings']
        texts = {n.get('text', '').strip().lower() for n in settings}
        if 'fingerprint added' in texts:
            for node in settings:
                if node.get('text', '').strip().lower() == 'done':
                    tap(node)
                    break
            (evidence / 'outcome.txt').write_text('Settings fingerprint enrollment completed; fingerprint ID 1\n')
            print('Settings fingerprint enrollment completed; real authentication checked by validate.py')
            break
        fields = [n for n in settings if n.get('class') == 'android.widget.EditText' and n.get('enabled') == 'true']
        if fields and not pin_entered:
            if len(fields) != 1 or not any('pin' in text for text in texts):
                raise RuntimeError('Unexpected Settings credential screen')
            if not tap(fields[0]):
                raise RuntimeError('Settings PIN field is not accessible')
            command('shell', 'input', 'text', '246813')
            command('shell', 'input', 'keyevent', 'KEYCODE_ENTER')
            pin_entered = True
        elif any(text in texts for text in ('touch the sensor', 'lift, then touch again')):
            if touches >= 12:
                raise RuntimeError('Enrollment did not complete within twelve sensor touches')
            command('emu', 'finger', 'touch', '1')
            time.sleep(.3)
            command('emu', 'finger', 'remove')
            touches += 1
        else:
            for node in settings:
                if node.get('text', '').strip().lower() in ('more', 'i agree', 'next') and tap(node):
                    break
        time.sleep(.5)
    else:
        raise RuntimeError('Settings enrollment did not reach Fingerprint added')
finally:
    # Only synthetic Settings UI; never persist the hierarchy or entered values.
    screenshot = subprocess.check_output(adb + ['exec-out', 'screencap', '-p'], timeout=15)
    (evidence / 'settings.png').write_bytes(screenshot)
command('shell', 'input', 'keyevent', 'KEYCODE_HOME')
