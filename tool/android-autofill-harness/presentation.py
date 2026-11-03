#!/usr/bin/env python3
"""Assert real synthetic presentation views and capture EN/PL day/night screenshots."""
import argparse
import json
import re
import sys
from pathlib import Path
import subprocess
import os
import time
import xml.etree.ElementTree as ET

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from android_harness_ui import launcher_anr_close

parser = argparse.ArgumentParser()
parser.add_argument('--serial', required=True)
args = parser.parse_args()
if not args.serial.startswith('emulator-'):
    raise RuntimeError('Presentation checks require an explicitly selected emulator')
adb = [os.environ.get('ADB', 'adb'), '-s', args.serial]
build = Path(__file__).resolve().parent / 'build/presentation'
build.mkdir(parents=True, exist_ok=True)
dismissed_launcher_anr = False
for language in ('en', 'pl'):
    for night in ('false', 'true'):
        subprocess.run(adb + ['shell', 'am', 'start', '-S', '-n', 'io.palladin.autofill.harness.provider/io.palladin.mobile.PresentationPreviewActivity', '--es', 'language', language, '--ez', 'night', night], check=True, stdout=subprocess.DEVNULL, timeout=30)
        expected = f'presentationVerified=true {language} night={night}'
        verified = False
        last_raw = None
        for attempt in range(3):
            time.sleep(.5)
            try:
                dump = subprocess.check_output(adb + ['shell', 'uiautomator', 'dump', '/sdcard/palladin-synthetic-ui.xml'], stderr=subprocess.STDOUT, timeout=15, text=True)
                if 'null root node returned by UiTestAutomationBridge' in dump:
                    continue
                raw = subprocess.check_output(adb + ['shell', 'cat', '/sdcard/palladin-synthetic-ui.xml'], timeout=5)
                last_raw = raw
                nodes = list(ET.fromstring(raw).iter('node'))
                close = launcher_anr_close(nodes)
                if close is not None and not dismissed_launcher_anr:
                    screenshot = subprocess.check_output(adb + ['exec-out', 'screencap', '-p'], timeout=15)
                    (build / 'launcher-anr-before-dismissal.png').write_bytes(screenshot)
                    x1, y1, x2, y2 = map(int, re.findall(r'\d+', close.get('bounds')))
                    subprocess.run(adb + ['shell', 'input', 'tap', str((x1+x2)//2), str((y1+y2)//2)], check=True, timeout=5)
                    dismissed_launcher_anr = True
                    (build / 'setup.json').write_text(json.dumps({'dismissedLauncherAnr': True}) + '\n')
                    continue
                if any("isn't responding" in n.get('text', '') for n in nodes):
                    break
                verified = any(n.get('text') == expected for n in nodes)
            finally:
                subprocess.run(adb + ['shell', 'rm', '-f', '/sdcard/palladin-synthetic-ui.xml'], check=True, timeout=5)
            if verified:
                break
        if not verified:
            if last_raw is not None:
                (build / f'{language}-night-{night}-failed.xml').write_bytes(last_raw)
            screenshot = subprocess.check_output(adb + ['exec-out', 'screencap', '-p'], timeout=15)
            (build / f'{language}-night-{night}-failed.png').write_bytes(screenshot)
            raise RuntimeError(f'Presentation assertions failed for {language} night={night}')
        screenshot = subprocess.check_output(adb + ['exec-out', 'screencap', '-p'], timeout=15)
        (build / f'{language}-night-{night}.png').write_bytes(screenshot)
        print(expected, flush=True)
