#!/usr/bin/env python3
"""Real OS save -> production MainActivity -> production Dart controller, synthetic values only."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
PROVIDER = 'io.palladin.autofill.savefixture.local'
FORM = 'io.palladin.autofill.savefixture.form'
SERVICE = PROVIDER + '/io.palladin.mobile.autofill.PalladinAutofillService'
MAIN = PROVIDER + '/io.palladin.mobile.MainActivity'
FORM_ACTIVITY = FORM + '/.SaveFormActivity'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--serial', required=True)
    args = parser.parse_args()
    if not re.fullmatch(r'emulator-\d+', args.serial) or not __debug__:
        raise RuntimeError('Requires an explicitly selected disposable emulator and enabled assertions')
    adb = os.environ.get('ADB', 'adb')

    def android(*parts):
        return subprocess.check_output([adb, '-s', args.serial, *parts], text=True, timeout=15).strip()

    def nodes():
        path = '/sdcard/palladin-synthetic-save-ui.xml'
        try:
            android('shell', 'uiautomator', 'dump', path)
            return list(ET.fromstring(android('shell', 'cat', path)).iter('node'))
        finally:
            android('shell', 'rm', '-f', path)

    def wait_text(pattern, tap=False):
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            for node in nodes():
                if re.fullmatch(pattern, node.get('text', ''), re.I):
                    if tap:
                        bounds = list(map(int, re.findall(r'\d+', node.get('bounds', ''))))
                        if len(bounds) != 4:
                            raise RuntimeError('UI target has no bounds')
                        x1, y1, x2, y2 = bounds
                        android('shell', 'input', 'tap', str((x1+x2)//2), str((y1+y2)//2))
                    return
            time.sleep(.2)
        raise RuntimeError('Expected synthetic UI state was not observed: ' + pattern)

    def tap(label):
        wait_text(re.escape(label), tap=True)

    def save_form():
        android('shell', 'am', 'force-stop', FORM)
        android('shell', 'am', 'start', '-n', FORM_ACTIVITY)
        tap('Request Autofill')
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            diagnosis = android('shell', 'dumpsys', 'activity', 'service', SERVICE)
            if re.search(r'result=(REJECTED|RESPONSE_OFFERED)', diagnosis):
                break
            time.sleep(.2)
        else:
            raise RuntimeError('Real service did not receive the form')
        tap('Populate synthetic fields')
        tap('Submit synthetic form')
        # This OS-owned button is essential evidence of the real SaveInfo contract.
        wait_text('Save', tap=True)

    source_status = subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT, text=True).strip()
    if source_status:
        raise RuntimeError('Runtime evidence requires a clean committed checkout')
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    build = json.loads((HERE / 'build/artifacts.json').read_text())
    if build['commit'] != commit or build.get('sourceClean') is not True:
        raise RuntimeError('Rebuild the exact committed checkout before runtime validation')
    for package in (PROVIDER, FORM):
        artifact = build['artifacts'][package]
        apk = ROOT / artifact['path']
        if hashlib.sha256(apk.read_bytes()).hexdigest() != artifact['sha256']:
            raise RuntimeError('APK hash differs from the validated build')
        android('install', '-r', str(apk))
        android('shell', 'pm', 'clear', package)
    previous = android('shell', 'settings', 'get', 'secure', 'autofill_service')
    report = {'commit': commit, 'artifacts': build['artifacts'], 'cases': []}
    try:
        android('shell', 'settings', 'put', 'secure', 'autofill_service', SERVICE)
        android('shell', 'pm', 'set-app-links', '--package', FORM, '2', 'fixture.invalid')
        android('shell', 'am', 'start', '-n', MAIN)
        wait_text('saveHarnessReady=true')
        save_form()
        wait_text('saveHandoffVerified=true')
        report['cases'].append({'case': 'os-save-to-production-flutter-controller', 'passed': True})

        tap('Hold pending save')
        wait_text('saveHoldReady=true')
        save_form()
        tap('Check pending')
        wait_text('savePendingVerified=true')
        tap('Revoke synthetic session')
        wait_text('saveRevokedVerified=true')
        tap('Arm save')
        wait_text('saveHarnessReady=true')
        tap('Check pending')
        wait_text('savePendingVerified=false')
        report['cases'].append({'case': 'revoke-discards-held-pending-save', 'passed': True})

        tap('Hold pending save')
        wait_text('saveHoldReady=true')
        save_form()
        tap('Check pending')
        wait_text('savePendingVerified=true')
        android('shell', 'am', 'force-stop', PROVIDER)
        android('shell', 'am', 'start', '-n', MAIN)
        wait_text('saveHarnessReady=true')
        tap('Check pending')
        wait_text('savePendingVerified=false')
        report['cases'].append({'case': 'process-death-discards-held-pending-save', 'passed': True})
        if (subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT, text=True).strip() or
                subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip() != commit):
            raise RuntimeError('Checkout changed during runtime validation')
        destination = HERE / 'build/validation.json'
        destination.write_text(json.dumps(report, indent=2) + '\n')
        for case in report['cases']:
            print(case['case'] + ': PASS')
    finally:
        if previous == 'null':
            android('shell', 'settings', 'delete', 'secure', 'autofill_service')
        else:
            android('shell', 'settings', 'put', 'secure', 'autofill_service', previous)
        for package in (FORM, PROVIDER):
            android('shell', 'am', 'force-stop', package)


if __name__ == '__main__':
    main()
