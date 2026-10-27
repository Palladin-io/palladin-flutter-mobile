#!/usr/bin/env python3
"""Build isolated debug APKs from unchanged product native sources and a synthetic Dart target."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
PROVIDER = 'io.palladin.autofill.savefixture.local'
FORM = 'io.palladin.autofill.savefixture.form'


def run(command, *, cwd=ROOT, env=None):
    subprocess.run(command, cwd=cwd, env=env, check=True, timeout=900)


def output(command):
    return subprocess.check_output(command, cwd=ROOT, text=True, timeout=30)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--gradle', default='gradle')
    parser.add_argument('--aapt', required=True)
    args = parser.parse_args()
    if not Path(args.aapt).is_file():
        raise RuntimeError('Supply the installed Android build-tools aapt executable')
    if (ROOT / 'android/key.properties').exists():
        raise RuntimeError('Synthetic build refuses release signing material')
    revision = output(['git', 'rev-parse', 'HEAD']).strip()
    clean_before = not output(['git', 'status', '--porcelain']).strip()
    run(['flutter', 'pub', 'get'])
    local_properties = ROOT / 'android/local.properties'
    if not local_properties.exists():
        flutter = shutil.which('flutter')
        sdk = os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT')
        if not flutter or not sdk:
            raise RuntimeError('Flutter and ANDROID_HOME are required')
        flutter_root = Path(flutter).resolve().parents[1]
        def escape(value):
            return str(value).replace('\\', '\\\\').replace(':', '\\:')
        local_properties.write_text('sdk.dir=' + escape(sdk) + '\nflutter.sdk=' + escape(flutter_root) + '\n')
    # Only this target/task-guarded debug subprocess bypasses the product's CI release-key check.
    debug_env = dict(os.environ, CI='false')
    run([args.gradle, '--no-daemon', ':app:assembleLocalDebug',
         '-I', str(HERE / 'synthetic-debug.init.gradle'),
         '-Ptarget=tool/android-autofill-save-harness/main.dart',
         '-Ptarget-platform=android-x64', '-Psplit-per-abi=true'],
        cwd=ROOT / 'android', env=debug_env)
    run([args.gradle, '--no-daemon', '-p', str(HERE), ':form:assembleDebug'])
    paths = {
        PROVIDER: ROOT / 'build/app/outputs/apk/local/debug/app-local-x86_64-debug.apk',
        FORM: HERE / 'form/build/outputs/apk/debug/form-debug.apk',
    }
    artifacts = {}
    for package, apk in paths.items():
        badging = output([args.aapt, 'dump', 'badging', str(apk)])
        if not re.search(r"package: name='" + re.escape(package) + "'", badging):
            raise RuntimeError('Unexpected synthetic APK identity')
        permissions = output([args.aapt, 'dump', 'permissions', str(apk)])
        if 'android.permission.INTERNET' in permissions:
            raise RuntimeError('Synthetic APK must not have network permission')
        manifest = output([args.aapt, 'dump', 'xmltree', str(apk), 'AndroidManifest.xml'])
        if 'com.google.firebase.provider.FirebaseInitProvider' in manifest:
            raise RuntimeError('Synthetic APK must not auto-initialize Firebase')
        if package == PROVIDER:
            resources = output([args.aapt, 'dump', 'resources', str(apk)])
            if any(name in resources for name in ('string/google_app_id', 'string/google_api_key',
                                                  'string/default_web_client_id')):
                raise RuntimeError('Synthetic APK contains cloud client configuration')
            if 'io.palladin.mobile.MainActivity' not in manifest:
                raise RuntimeError('Production MainActivity is missing')
        artifacts[package] = {'path': str(apk.relative_to(ROOT)),
                              'sha256': hashlib.sha256(apk.read_bytes()).hexdigest()}
    clean_after = not output(['git', 'status', '--porcelain']).strip()
    unchanged = output(['git', 'rev-parse', 'HEAD']).strip() == revision
    result = {'commit': revision, 'sourceClean': clean_before and clean_after and unchanged,
              'artifacts': artifacts}
    destination = HERE / 'build/artifacts.json'
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(result, indent=2) + '\n')
    print('Synthetic save APK identity/network checks passed')


if __name__ == '__main__':
    main()
