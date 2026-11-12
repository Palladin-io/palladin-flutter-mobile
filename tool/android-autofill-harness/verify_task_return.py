#!/usr/bin/env python3
"""Check OS task/result return using isolated synthetic APKs on an emulator."""
import argparse
from pathlib import Path
import re
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument('--serial', required=True)
parser.add_argument('--home-behind-picker', action='store_true')
parser.add_argument('--password-only', action='store_true')
args = parser.parse_args()
if not args.serial.startswith('emulator-'):
    parser.error('Disposable emulator required; never run on a user phone')
base = Path(__file__).resolve().parent

def adb(*values):
    return subprocess.check_output(['adb', '-s', args.serial, *values], text=True).strip()

provider = 'io.palladin.autofill.harness.provider'
requester = 'io.palladin.autofill.harness.form'
for module in ['provider', 'form']:
    adb('install', '-r', str(base / module / 'build/outputs/apk/debug' / f'{module}-debug.apk'))
prior_policy = adb('shell', 'settings', 'get', 'global', 'hidden_api_policy')
if args.password_only:
    adb('shell', 'settings', 'put', 'global', 'hidden_api_policy', '1')
try:
    for package in [provider, requester]:
        adb('shell', 'am', 'force-stop', package)
    adb('shell', 'am', 'start', '-W', '-n', f'{provider}/io.palladin.mobile.ReturnPickerProbe')
    adb('shell', 'input', 'keyevent', 'KEYCODE_HOME')
    adb('shell', 'am', 'start', '-W', '-n', f'{requester}/io.palladin.autofill.form.ReturnRequesterProbe', '--ez', 'homeBehindPicker', str(args.home_behind_picker).lower(), '--ez', 'passwordOnly', str(args.password_only).lower())
    result = ''
    for _ in range(30):
        time.sleep(.2)
        result = adb('shell', 'run-as', requester, 'cat', 'files/return-result')
        if result != 'pending':
            break
    time.sleep(.5)
    activities = adb('shell', 'dumpsys', 'activity', 'activities')
    resumed = [component for line in activities.splitlines() if 'ResumedActivity' in line
               for component in re.findall(r'[A-Za-z][\w.]*/[\w.$]+', line)]
    original_in_app_tasks = adb('shell', 'run-as', provider, 'cat', 'files/return-app-task-owner')
    print(f'result={result}; original_task_in_app_tasks={original_in_app_tasks}; resumed={resumed}')
    assert result == 'verified=true;count=1', 'Original result receiver did not receive exactly one success'
    assert f'{requester}/io.palladin.autofill.form.ReturnRequesterProbe' in resumed, 'Original requester task did not resume'
finally:
    if args.password_only:
        if prior_policy == 'null':
            adb('shell', 'settings', 'delete', 'global', 'hidden_api_policy')
        else:
            adb('shell', 'settings', 'put', 'global', 'hidden_api_policy', prior_policy)
