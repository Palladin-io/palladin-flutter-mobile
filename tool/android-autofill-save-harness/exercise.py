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


def read_nodes(android):
    path = '/sdcard/palladin-synthetic-save-ui.xml'
    android('shell', 'rm', '-f', path)
    try:
        android('shell', 'uiautomator', 'dump', '--windows', path)
        try:
            android('shell', 'test', '-s', path)
        except subprocess.CalledProcessError as error:
            if error.returncode == 1:
                return []
            raise
        return list(ET.fromstring(android('shell', 'cat', path)).iter('node'))
    finally:
        android('shell', 'rm', '-f', path)


def matches_label(node, pattern):
    return node.get('enabled') == 'true' and any(
        re.fullmatch(pattern, node.get(attribute, ''), re.I) is not None
        for attribute in ('text', 'content-desc'))


def launcher_anr_close(nodes):
    titles = [node for node in nodes if "isn't responding" in node.get('text', '')]
    if (len(titles) != 1 or titles[0].get('text') != "Pixel Launcher isn't responding"
            or titles[0].get('package') != 'android'):
        return None
    controls = [node for node in nodes if node.get('text') == 'Close app']
    if len(controls) != 1:
        return None
    control = controls[0]
    if (control.get('package') != 'android' or control.get('class') != 'android.widget.Button'
            or control.get('enabled') != 'true'
            or not re.fullmatch(r'\[\d+,\d+\]\[\d+,\d+\]', control.get('bounds', ''))):
        return None
    return control


def hierarchy_metadata(nodes):
    roles = {'android.view.View', 'android.widget.TextView', 'android.widget.Button',
             'android.widget.EditText', 'android.widget.FrameLayout', 'android.widget.LinearLayout'}
    labels = {'coldStartEmpty': 'saveColdStartEmpty=true',
              'coldStartNotEmpty': 'saveColdStartEmpty=false',
              'armButton': 'Arm save', 'harnessInitial': 'saveHarnessReady=false'}
    result = []
    for node in nodes:
        bounds = node.get('bounds', '')
        result.append({
            'role': node.get('class') if node.get('class') in roles else 'other',
            'bounds': list(map(int, re.findall(r'\d+', bounds)))
                      if re.fullmatch(r'\[\d+,\d+\]\[\d+,\d+\]', bounds) else None,
            'enabled': node.get('enabled') == 'true',
            **{key: any(node.get(attribute) == value for attribute in ('text', 'content-desc'))
               for key, value in labels.items()},
        })
    return result


def failure_state(android):
    def read(*parts):
        try:
            return android(*parts)
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
            return None
    activities = read('shell', 'dumpsys', 'activity', 'activities')
    resumed = None if activities is None else '\n'.join(
        line for line in activities.splitlines()
        if 'mResumedActivity' in line or 'topResumedActivity' in line)
    processes = read('shell', 'ps', '-A', '-o', 'NAME')
    service = read('shell', 'dumpsys', 'activity', 'service', SERVICE)
    return {
        'providerProcessPresent': None if processes is None else PROVIDER in processes.splitlines(),
        'formProcessPresent': None if processes is None else FORM in processes.splitlines(),
        'providerResumed': None if resumed is None else PROVIDER + '/' in resumed,
        'formResumed': None if resumed is None else FORM + '/' in resumed,
        'serviceCallbackObserved': None if service is None else 'result=' in service,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--serial', required=True)
    args = parser.parse_args()
    if not re.fullmatch(r'emulator-\d+', args.serial) or not __debug__:
        raise RuntimeError('Requires an explicitly selected disposable emulator and enabled assertions')
    adb = os.environ.get('ADB', 'adb')

    def android(*parts):
        return subprocess.check_output([adb, '-s', args.serial, *parts], text=True, timeout=15).strip()

    dismissed_launcher_anr = False

    def tap_node(node):
        bounds = list(map(int, re.findall(r'\d+', node.get('bounds', ''))))
        if len(bounds) != 4:
            raise RuntimeError('UI target has no bounds')
        x1, y1, x2, y2 = bounds
        if x2 <= x1 or y2 <= y1:
            raise RuntimeError('UI target has empty bounds')
        android('shell', 'input', 'tap', str((x1+x2)//2), str((y1+y2)//2))

    def wait_text(pattern, tap=False, allow_launcher_dismiss=False):
        nonlocal dismissed_launcher_anr
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            nodes = read_nodes(android)
            if allow_launcher_dismiss and not dismissed_launcher_anr:
                close = launcher_anr_close(nodes)
                if close is not None:
                    tap_node(close)
                    dismissed_launcher_anr = True
                    continue
            for node in nodes:
                if matches_label(node, pattern):
                    if tap:
                        tap_node(node)
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
    stage = 'cold-start'
    try:
        android('shell', 'settings', 'put', 'secure', 'autofill_service', SERVICE)
        android('shell', 'pm', 'set-app-links', '--package', FORM, '2', 'fixture.invalid')
        android('shell', 'am', 'start', '-n', MAIN)
        wait_text('saveColdStartEmpty=true', allow_launcher_dismiss=True)
        tap('Arm save')
        wait_text('saveHarnessReady=true')
        stage = 'positive-save'
        save_form()
        wait_text('saveHandoffVerified=true')
        report['cases'].append({'case': 'os-save-to-production-flutter-controller', 'passed': True})

        stage = 'revoke-negative'
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

        stage = 'process-death-negative'
        tap('Hold pending save')
        wait_text('saveHoldReady=true')
        save_form()
        tap('Check pending')
        wait_text('savePendingVerified=true')
        android('shell', 'am', 'force-stop', PROVIDER)
        android('shell', 'am', 'start', '-n', MAIN)
        wait_text('saveColdStartEmpty=true')
        report['cases'].append({'case': 'process-death-discards-held-pending-save', 'passed': True})
        if (subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT, text=True).strip() or
                subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip() != commit):
            raise RuntimeError('Checkout changed during runtime validation')
        report['dismissedLauncherAnr'] = dismissed_launcher_anr
        destination = HERE / 'build/validation.json'
        destination.write_text(json.dumps(report, indent=2) + '\n')
        for case in report['cases']:
            print(case['case'] + ': PASS')
    except Exception:
        failure = {'commit': commit, 'stage': stage, 'dismissedLauncherAnr': dismissed_launcher_anr,
                   **failure_state(android)}
        try:
            failure['hierarchy'] = hierarchy_metadata(read_nodes(android))
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired, ET.ParseError):
            failure['hierarchy'] = None
        # This driver accepts only a fresh synthetic emulator and only fixture APKs.
        if failure['providerResumed'] is True or failure['formResumed'] is True:
            screenshot = HERE / 'build/synthetic-failure.png'
            try:
                with screenshot.open('wb') as image:
                    subprocess.run([adb, '-s', args.serial, 'exec-out', 'screencap', '-p'],
                                   stdout=image, stderr=subprocess.DEVNULL, check=True, timeout=15)
            except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
                screenshot.unlink(missing_ok=True)
        (HERE / 'build/failure.json').write_text(json.dumps(failure, indent=2) + '\n')
        raise
    finally:
        if previous == 'null':
            android('shell', 'settings', 'delete', 'secure', 'autofill_service')
        else:
            android('shell', 'settings', 'put', 'secure', 'autofill_service', previous)
        for package in (FORM, PROVIDER):
            android('shell', 'am', 'force-stop', package)


if __name__ == '__main__':
    main()
