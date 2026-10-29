#!/usr/bin/env python3
"""Bounded renderer comparison; never produces full AutoFill acceptance evidence."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
SERIAL = 'emulator-5554'


def file_hash(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def compare_result(results):
    return len(results) == 2 and all(result['passedCases'] == 10 and result['failureStage'] is None for result in results)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--gradle', required=True)
    args = parser.parse_args()
    if os.environ.get('GITHUB_ACTIONS') != 'true' or not os.environ.get('RUNNER_TEMP'):
        raise RuntimeError('Renderer comparison requires a disposable CI runner')
    sdk = Path(os.environ['ANDROID_HOME'])
    adb = str(sdk / 'platform-tools/adb')
    emulator = str(sdk / 'emulator/emulator')
    evidence = HERE / 'build/transport-probe'
    evidence.mkdir(parents=True, exist_ok=True)

    def run(command, *, timeout=15, **kwargs):
        return subprocess.run(command, cwd=ROOT, check=True, timeout=timeout, **kwargs)

    def output(command, timeout=15):
        return subprocess.check_output(command, cwd=ROOT, text=True, timeout=timeout).strip()

    if output(['git', 'status', '--porcelain']):
        raise RuntimeError('Probe requires a clean committed checkout')
    commit = output(['git', 'rev-parse', 'HEAD'])
    run([args.gradle, '-p', str(HERE), 'clean', ':provider:testDebugUnitTest', ':form:testDebugUnitTest', 'assembleDebug'], timeout=600)
    # Gradle clean removes build/, so create the evidence destination afterwards.
    evidence.mkdir(parents=True, exist_ok=True)
    apks = {module: HERE / module / f'build/outputs/apk/debug/{module}-debug.apk' for module in ('provider', 'form')}
    hashes = {module: file_hash(path) for module, path in apks.items()}
    report = {'purpose': 'TRANSPORT_PROBE_NOT_ACCEPTANCE', 'commit': commit, 'apkSha256': hashes,
              'emulatorVersion': output([emulator, '-version']),
              'emulatorSha256': file_hash(Path(emulator)),
              'systemImageSha256': file_hash(sdk / 'system-images/android-35/google_apis/x86_64/system.img'),
              'results': []}
    env = {**os.environ, 'ADB': adb}
    android = [adb, '-s', SERIAL]
    for renderer in ('software', 'swiftshader'):
        destination = evidence / renderer
        destination.mkdir(parents=True, exist_ok=True)
        result = {'renderer': renderer, 'passedCases': 0, 'failureStage': None}
        process = None
        avd = Path(tempfile.mkdtemp(prefix='palladin-renderer-', dir=os.environ['RUNNER_TEMP']))
        avd_env = {**env, 'ANDROID_AVD_HOME': str(avd)}
        stage = 'create-avd'
        try:
            if SERIAL in output([adb, 'devices']):
                raise RuntimeError('Probe serial is already occupied')
            run([str(sdk / 'cmdline-tools/latest/bin/avdmanager'), 'create', 'avd', '--name', 'palladin-probe', '--package', 'system-images;android-35;google_apis;x86_64', '--device', 'pixel_2'], input=b'no\n', env=avd_env, timeout=60)
            with (destination / 'emulator.log').open('wb') as emulator_log, (destination / 'cases.log').open('wb') as case_log:
                process = subprocess.Popen([emulator, '-avd', 'palladin-probe', '-port', '5554', '-no-window', '-no-audio', '-no-snapshot', '-no-boot-anim', '-gpu', renderer, '-memory', '2048'], env=avd_env, stdout=emulator_log, stderr=subprocess.STDOUT)
                stage = 'boot'
                deadline = time.monotonic() + 180
                while time.monotonic() < deadline:
                    try:
                        ready = subprocess.run(android + ['shell', 'getprop', 'sys.boot_completed'], capture_output=True, timeout=5)
                    except subprocess.TimeoutExpired:
                        ready = None
                    if ready is not None and ready.stdout.strip() == b'1':
                        break
                    if process.poll() is not None:
                        raise RuntimeError('Emulator exited before boot')
                    time.sleep(2)
                else:
                    raise RuntimeError('Boot deadline')
                stage = 'setup'
                run(android + ['shell', 'input', 'keyevent', '82'], timeout=10)
                run(android + ['shell', 'cmd', 'device_config', 'set_sync_disabled_for_tests', 'until_reboot'], timeout=10)
                if output(android + ['shell', 'cmd', 'device_config', 'get_sync_disabled_for_tests']) != 'until_reboot':
                    raise RuntimeError('Config synchronization was not isolated')
                for animation in ('window_animation_scale', 'transition_animation_scale', 'animator_duration_scale'):
                    run(android + ['shell', 'settings', 'put', 'global', animation, '0'], timeout=10)
                for path in apks.values():
                    run(android + ['install', '-r', str(path)], timeout=45)
                run(android + ['shell', 'settings', 'put', 'secure', 'autofill_service', 'io.palladin.autofill.harness.provider/io.palladin.mobile.autofill.PalladinAutofillService'])
                run(android + ['shell', 'settings', 'put', 'secure', 'show_ime_with_hard_keyboard', '1'])
                for script in ('presentation.py', 'prepare_ci.py'):
                    stage = script
                    run([sys.executable, '-u', str(HERE / script), '--serial', SERIAL], env=env, stdout=case_log, stderr=subprocess.STDOUT, timeout=240)
                run(android + ['shell', 'am', 'start', '-n', 'io.palladin.autofill.harness.provider/io.palladin.mobile.MainActivity'])
                for iteration in range(5):
                    for mode in ('web-login', 'web-username'):
                        stage = f'{iteration + 1}-{mode}'
                        run([sys.executable, '-u', str(HERE / 'exercise.py'), '--serial', SERIAL, '--mode', mode, '--fill'], env=env, stdout=case_log, stderr=subprocess.STDOUT, timeout=180)
                        result['passedCases'] += 1
        except (subprocess.SubprocessError, RuntimeError, OSError) as error:
            result['failureStage'] = stage
            result['failureClass'] = type(error).__name__
            result['failureExit'] = getattr(error, 'returncode', None)
        finally:
            result['emulatorExitBeforeCleanup'] = process.poll() if process else None
            result['portsOpen'] = {}
            for port in (5554, 5555, 5037):
                with socket.socket() as connection:
                    connection.settimeout(1)
                    result['portsOpen'][str(port)] = connection.connect_ex(('127.0.0.1', port)) == 0
            for name, command in {'adbState': ['get-state'], 'guestBoot': ['shell', 'getprop', 'sys.boot_completed'], 'guestAdbd': ['shell', 'pidof', 'adbd']}.items():
                try:
                    state = subprocess.run(android + command, capture_output=True, text=True, timeout=5)
                    value = state.stdout.strip()
                    result[name] = {'exit': state.returncode, 'value': value if value in ('device', 'offline', '1') or (name == 'guestAdbd' and value.isdigit()) else 'UNAVAILABLE'}
                except subprocess.TimeoutExpired:
                    result[name] = {'exit': 'TIMEOUT'}
            if process and process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)
            for folder in ('presentation', 'enrollment', 'exercise'):
                source = HERE / 'build' / folder
                if source.exists():
                    shutil.copytree(source, destination / folder)
                    shutil.rmtree(source)
            shutil.rmtree(avd)
            report['results'].append(result)
            (evidence / 'probe.json').write_text(json.dumps(report, indent=2) + '\n')
        for _ in range(10):
            if SERIAL not in output([adb, 'devices']):
                break
            time.sleep(1)
        else:
            raise RuntimeError('Previous emulator transport remains; refusing second AVD')
    if hashes != {module: file_hash(path) for module, path in apks.items()} or output(['git', 'status', '--porcelain']) or output(['git', 'rev-parse', 'HEAD']) != commit:
        raise RuntimeError('Probe source or APK identity changed')
    report['sourceClean'] = True
    report['comparisonPassed'] = compare_result(report['results'])
    (evidence / 'probe.json').write_text(json.dumps(report, indent=2) + '\n')
    if not report['comparisonPassed']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
