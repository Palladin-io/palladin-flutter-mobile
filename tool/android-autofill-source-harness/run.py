#!/usr/bin/env python3
"""Real MainActivity/MethodChannel smoke test on an explicitly selected emulator."""
import argparse
from pathlib import Path
import re
import subprocess
import time
import xml.etree.ElementTree as ET

PACKAGE = 'io.palladin.autofill.sourcefixture.local'
FORM = 'io.palladin.mobile.autofill.SourceFixtureActivity'
MAIN = 'io.palladin.mobile.MainActivity'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--adb', required=True)
    parser.add_argument('--serial', required=True)
    parser.add_argument('--apk', required=True)
    parser.add_argument('--aapt', required=True)
    parser.add_argument('--legacy-only', action='store_true')
    args = parser.parse_args()
    if not args.serial.startswith('emulator-'):
        raise RuntimeError('Only an explicitly selected emulator is supported')
    def adb(*items):
        return subprocess.check_output([args.adb, '-s', args.serial, *items], text=True, timeout=45)
    apk = str(Path(args.apk).resolve())
    permissions = subprocess.check_output([args.aapt, 'dump', 'permissions', apk], text=True)
    if 'android.permission.INTERNET' in permissions:
        raise RuntimeError('Network-capable fixture refused')
    badging = subprocess.check_output([args.aapt, 'dump', 'badging', apk], text=True)
    if f"package: name='{PACKAGE}'" not in badging:
        raise RuntimeError('Unexpected fixture package')
    manifest = subprocess.check_output([args.aapt, 'dump', 'xmltree', apk, 'AndroidManifest.xml'], text=True)
    resources = subprocess.check_output([args.aapt, 'dump', 'resources', apk], text=True)
    if 'com.google.firebase.provider.FirebaseInitProvider' in manifest or any(
        name in resources for name in ('string/google_app_id', 'string/google_api_key', 'string/default_web_client_id')
    ):
        raise RuntimeError('Cloud-configured fixture refused')
    adb('install', '-r', apk)
    adb('shell', 'am', 'force-stop', PACKAGE)
    def nodes():
        adb('shell', 'rm', '-f', '/sdcard/source-fixture-window.xml')
        adb('shell', 'uiautomator', 'dump', '/sdcard/source-fixture-window.xml')
        try:
            return ET.fromstring(adb('shell', 'cat', '/sdcard/source-fixture-window.xml')).iter('node')
        except (subprocess.CalledProcessError, ET.ParseError):
            return iter(())
    def await_text(text):
        for _ in range(15):
            tree = list(nodes())
            if any(value in ('LEGACY_CACHE_TOUCHED', 'SOURCE_OWNER_FAIL', 'SOURCE_HARD_REPAIR_FAIL', 'SOURCE_BOOTSTRAP_FAIL')
                   for node in tree for value in (node.get('text'), node.get('content-desc'))):
                raise AssertionError('Native owner violated expected fixture boundary')
            match = next((node for node in tree if text in (node.get('text'), node.get('content-desc'))), None)
            if match is not None:
                return match
            time.sleep(.5)
        raise AssertionError(f'Missing fixed fixture marker: {text}')
    def launch(component, *extras):
        adb('shell', 'am', 'start', '-n', f'{PACKAGE}/{component}', '-f', '0x24000000', *extras)
    cases = () if args.legacy_only else (('cold', False), ('warm', False), ('warm-username', True))
    for temperature, username_only in cases:
        adb('shell', 'am', 'force-stop', 'io.palladin.autofill.harness.form')
        launch(FORM, '--ez', 'usernameOnly', str(username_only).lower())
        button = await_text('Open native request')
        left, top, right, bottom = map(int, re.findall(r'\d+', button.get('bounds')))
        adb('shell', 'input', 'tap', str((left + right)//2), str((top + bottom)//2))
        await_text('SOURCE_OWNER_CANCEL_PASS')
        launch(MAIN)
        await_text('SOURCE_CHANNEL_USERNAME_CANCEL_PASS' if username_only else 'SOURCE_CHANNEL_CANCEL_PASS')
        print(f'PASS {temperature}: actual Flutter pending/bind/auth rejection/cancel/original-owner')
    if not args.legacy_only:
        button = await_text('Verify hard revoke repair')
        left, top, right, bottom = map(int, re.findall(r'\d+', button.get('bounds')))
        adb('shell', 'input', 'tap', str((left + right)//2), str((top + bottom)//2))
        await_text('SOURCE_HARD_REPAIR_PASS')
        print('PASS live hard revoke: same owning session repairs exact epoch', flush=True)
        adb('shell', 'am', 'force-stop', PACKAGE)
        launch(MAIN)
        button = await_text('Verify protected bootstrap')
        left, top, right, bottom = map(int, re.findall(r'\d+', button.get('bounds')))
        adb('shell', 'input', 'tap', str((left + right)//2), str((top + bottom)//2))
        await_text('SOURCE_BOOTSTRAP_PASS')
        print('PASS process death: protected config, exact adoption, forced quarantine', flush=True)
    launch(FORM, '--ez', 'legacy', 'true')
    button = await_text('Open native request')
    left, top, right, bottom = map(int, re.findall(r'\d+', button.get('bounds')))
    adb('shell', 'input', 'tap', str((left + right)//2), str((top + bottom)//2))
    await_text('LEGACY_CACHE_UNTOUCHED')
    print('PASS legacy credential intent: canceled without old cache access', flush=True)
    adb('shell', 'rm', '/sdcard/source-fixture-window.xml')


if __name__ == '__main__':
    main()
