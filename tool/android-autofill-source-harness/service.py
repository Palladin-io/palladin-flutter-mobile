#!/usr/bin/env python3
"""Assert real system FillResponses without provisioning a second credential cache."""
import argparse
import re
import subprocess
import time
import xml.etree.ElementTree as ET


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--adb', required=True)
    parser.add_argument('--serial', required=True)
    args = parser.parse_args()
    if not args.serial.startswith('emulator-'):
        raise RuntimeError('Synthetic emulator only')
    def adb(*items):
        return subprocess.check_output([args.adb, '-s', args.serial, *items], text=True, timeout=30)
    provider = 'io.palladin.autofill.sourcefixture.local'
    form = 'io.palladin.autofill.harness.form'
    service = provider + '/io.palladin.mobile.autofill.PalladinAutofillService'
    previous = adb('shell', 'settings', 'get', 'secure', 'autofill_service').strip()
    try:
        adb('shell', 'settings', 'put', 'secure', 'autofill_service', service)
        for mode, expected in [('native-login', 'RESPONSE_OFFERED'), ('native-username', 'RESPONSE_OFFERED'),
                               ('native-otp', 'REJECTED')]:
            adb('shell', 'am', 'force-stop', form)
            adb('shell', 'am', 'force-stop', provider)
            adb('shell', 'am', 'start', '-n', form + '/io.palladin.autofill.form.FormActivity', '--es', 'mode', mode)
            button = None
            for _ in range(6):
                adb('shell', 'uiautomator', 'dump', '/sdcard/source-service.xml')
                try:
                    nodes = list(ET.fromstring(adb('shell', 'cat', '/sdcard/source-service.xml')).iter('node'))
                    button = next((n for n in nodes if n.get('text', '').lower() == 'request autofill'), None)
                except (ET.ParseError, subprocess.CalledProcessError):
                    pass
                if button is not None:
                    break
                time.sleep(.3)
            if button is None:
                raise AssertionError('Synthetic request control absent')
            x1,y1,x2,y2 = map(int, re.findall(r'\d+', button.get('bounds')))
            adb('shell', 'input', 'tap', str((x1+x2)//2), str((y1+y2)//2))
            result = None
            for _ in range(30):
                diagnostic = adb('shell', 'dumpsys', 'activity', 'service', service)
                result = re.search(r'result=(RESPONSE_OFFERED|REJECTED)', diagnostic)
                if result:
                    break
                time.sleep(.1)
            assert result and result[1] == expected, f'{mode}: expected {expected}, observed {result[1] if result else "NO_DIAGNOSIS"}'
            print(f'PASS {mode}: {expected}, no native credential cache', flush=True)
    finally:
        if previous == 'null':
            adb('shell', 'settings', 'delete', 'secure', 'autofill_service')
        else:
            adb('shell', 'settings', 'put', 'secure', 'autofill_service', previous)
        adb('shell', 'rm', '-f', '/sdcard/source-service.xml')


if __name__ == '__main__':
    main()
