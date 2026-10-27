#!/usr/bin/env python3
"""Assert real synthetic presentation views and capture EN/PL day/night screenshots."""
import argparse
from pathlib import Path
import subprocess
import os
import time
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser()
parser.add_argument('--serial', required=True)
args = parser.parse_args()
if not args.serial.startswith('emulator-'):
    raise RuntimeError('Presentation checks require an explicitly selected emulator')
adb = [os.environ.get('ADB', 'adb'), '-s', args.serial]
build = Path(__file__).resolve().parent / 'build/presentation'
build.mkdir(parents=True, exist_ok=True)
for language in ('en', 'pl'):
    for night in ('false', 'true'):
        subprocess.run(adb + ['shell', 'am', 'start', '-S', '-n', 'io.palladin.autofill.harness.provider/io.palladin.mobile.PresentationPreviewActivity', '--es', 'language', language, '--ez', 'night', night], check=True, stdout=subprocess.DEVNULL, timeout=30)
        expected = f'presentationVerified=true {language} night={night}'
        verified = False
        for attempt in range(3):
            time.sleep(.5)
            try:
                subprocess.run(adb + ['shell', 'uiautomator', 'dump', '/sdcard/palladin-synthetic-ui.xml'], check=True, stdout=subprocess.DEVNULL, timeout=15)
                raw = subprocess.check_output(adb + ['shell', 'cat', '/sdcard/palladin-synthetic-ui.xml'], timeout=5)
                verified = any(n.get('text') == expected for n in ET.fromstring(raw).iter('node'))
            finally:
                subprocess.run(adb + ['shell', 'rm', '-f', '/sdcard/palladin-synthetic-ui.xml'], check=True, timeout=5)
            if verified:
                break
        if not verified:
            raise RuntimeError(f'Presentation assertions failed for {language} night={night}')
        screenshot = subprocess.check_output(adb + ['exec-out', 'screencap', '-p'], timeout=15)
        (build / f'{language}-night-{night}.png').write_bytes(screenshot)
        print(expected, flush=True)
