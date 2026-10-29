#!/usr/bin/env python3
"""Exercise installed synthetic APKs on an explicitly selected disposable emulator."""
import argparse
import json
import math
from pathlib import Path
import os
import re
import subprocess
import time
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser()
parser.add_argument('--serial', required=True)
parser.add_argument('--mode', choices=['native-login', 'native-username', 'native-username-hint', 'native-login-opaque', 'native-username-manual', 'native-username-manual-verified', 'web-login', 'web-username', 'web-http', 'web-missing', 'web-empty', 'native-empty', 'web-search', 'web-otp', 'web-confirm', 'web-hidden', 'web-disabled', 'native-search', 'native-otp', 'native-confirm', 'native-hidden', 'native-disabled', 'native-container', 'native-username-manual-password', 'web-username-manual', 'native-username-manual-cancel'], required=True)
parser.add_argument('--expected', choices=['RESPONSE_OFFERED', 'REJECTED', 'NO_RESPONSE'], default='RESPONSE_OFFERED')
parser.add_argument('--fill', action='store_true')
parser.add_argument('--inspect-response', action='store_true')
parser.add_argument('--inline-mode', choices=['supported', 'absent', 'unsupported'], default='supported')
args = parser.parse_args()
if not args.serial.startswith('emulator-'):
    raise RuntimeError('This harness only operates on an emulator')
if not __debug__:
    raise RuntimeError('Run without Python optimization so every field assertion is checked')
adb = os.environ.get('ADB', 'adb')
form = 'io.palladin.autofill.harness.form'
provider = 'io.palladin.autofill.harness.provider'
service = provider + '/io.palladin.mobile.autofill.PalladinAutofillService'


def command(*parts):
    return subprocess.check_output([adb, '-s', args.serial, *parts], text=True, timeout=15, stderr=subprocess.STDOUT)


def nodes():
    try:
        status = command('shell', 'uiautomator', 'dump', '--windows', '/sdcard/palladin-synthetic-ui.xml')
        if status.strip() == 'ERROR: null root node returned by UiTestAutomationBridge.':
            return []
        raw = command('shell', 'cat', '/sdcard/palladin-synthetic-ui.xml')
        return list(ET.fromstring(raw).iter('node'))
    finally:
        command('shell', 'rm', '-f', '/sdcard/palladin-synthetic-ui.xml')


def tap_node(node):
    bounds = list(map(int, re.findall(r'\d+', node.get('bounds', ''))))
    if len(bounds) != 4:
        return False
    x1, y1, x2, y2 = bounds
    if x2 <= x1 or y2 <= y1 or node.get('enabled') == 'false':
        return False
    command('shell', 'input', 'tap', str((x1+x2)//2), str((y1+y2)//2))
    return True


def wait_for(predicate, message):
    for _ in range(6):
        if predicate(nodes()):
            return
        time.sleep(.3)
    raise AssertionError(message)


def tap_text(pattern):
    for _ in range(4):
        for node in nodes():
            if any(re.search(pattern, node.get(key, ''), re.I)
                   for key in ('text', 'content-desc')) and tap_node(node):
                return True
        time.sleep(.3)
    if pattern in ('Unlock Palladin to autofill', '^synthetic-user$'):
        ime = command('shell', 'settings', 'get', 'secure', 'default_input_method').strip().split('/')[0]
        candidates = []
        for container in nodes():
            if (container.get('package') != ime or container.get('resource-id') !=
                    ime + ':id/key_pos_proactive_suggestions'):
                continue
            # The recorded API 35 IME exposes the chip container but omits its
            # embedded title. Use its actual accessible bounds, only if unique.
            candidates.extend(node for node in container.iter('node') if
                node.get('package') == ime and node.get('class') == 'android.view.ViewGroup' and
                all(node.get(key) == 'true' for key in ('enabled', 'clickable', 'focusable')))
        if len(candidates) == 1:
            return tap_node(candidates[0])
    return False


def focus_field(required=True):
    # Native EditText and WebView's virtual input accessibility nodes share this
    # public class name. The source package prevents targeting system UI fields.
    for _ in range(6 if required else 1):
        for node in nodes():
            if (node.get('package') == form and
                    node.get('class') == 'android.widget.EditText' and tap_node(node)):
                return
        time.sleep(.3)
    if required:
        raise AssertionError('Synthetic focus field not exposed by accessibility')


def request_snapshot(diagnosis):
    allowed = {
        'domains': {'NOT_CHECKED', 'ZERO', 'ONE', 'AMBIGUOUS'},
        'origin': {'NOT_CHECKED', 'QUERY_UNAVAILABLE', 'LINK_HANDLING_DISABLED', 'UNVERIFIED', 'VERIFIED'},
        'result': {'NO_REQUEST', 'CHECKING', 'CANCELED', 'NO_STRUCTURE', 'REJECTED', 'RESPONSE_OFFERED'},
    }
    snapshot = {}
    for line in diagnosis.splitlines():
        key, separator, value = line.strip().partition('=')
        if separator and value in allowed.get(key, set()):
            snapshot[key] = value
    return snapshot


def assert_web_origin(diagnosis):
    snapshot = request_snapshot(diagnosis)
    assert (snapshot.get('domains') == 'ONE' and
            snapshot.get('origin') == 'VERIFIED'), 'Web fixture did not report one verified domain'


def negative_outcome(diagnosis, tree, selected_provider, mode, password_null=False):
    assert selected_provider == service, 'Expected AutoFill provider is not selected'
    snapshot = request_snapshot(diagnosis)
    assert snapshot.get('result') != 'RESPONSE_OFFERED', 'Negative fixture offered credentials'
    assert not any(node.get('package') == provider or
                   (node.get('package') == 'com.android.systemui' and node.get('text') == 'Unlock Palladin')
                   for node in tree), 'Negative fixture opened authentication'
    texts = {node.get('text') for node in tree if node.get('package') == form}
    states = [text for text in texts if text and text.startswith('requestIssued=')]
    assert len(states) == 1, 'Current fixture evidence missing or ambiguous'
    state = dict(part.split('=', 1) for part in states[0].split())
    assert all(state.get(key) == 'true' for key in ('requestIssued', 'enabled', 'domReady')), 'Fresh ready enabled request not established'
    assert state.get('uiShown') == 'false' and state.get('shownEvents') == '0', 'AutoFill UI was shown'
    assert mode == 'web-http' or state.get('focusVerified') == 'true', 'Fixture input was not focused'
    assert 'fieldsUnchanged=true' in texts, 'Negative fixture fields changed'
    if snapshot.get('result') == 'REJECTED':
        return 'REJECTED'
    assert snapshot.get('result') == 'NO_REQUEST' or 'No services match' in diagnosis, 'Unknown provider outcome'
    if state.get('unavailable') == 'true':
        count = state.get('unavailableEvents', '')
        assert count.isdigit() and int(count) > 0, 'Missing current system-unavailable event count'
        return 'SYSTEM_UNAVAILABLE'
    if password_null:
        assert state.get('unavailable') == 'false' and state.get('unavailableEvents') == '0'
        return 'SYSTEM_NULL_PASSWORD'
    if mode == 'native-container':
        assert state.get('noneditableTarget') == 'true', 'Target was not proven noneditable'
        assert any(node.get('package') == form and node.get('class') == 'android.widget.TextView'
                   and node.get('focused') == 'true' and node.get('text') == 'Synthetic label'
                   for node in tree), 'Focused noneditable target is missing'
        assert state.get('unavailable') == 'false' and state.get('unavailableEvents') == '0'
        return 'PLATFORM_INELIGIBLE'
    assert mode.startswith('web') and state.get('unavailable') == 'false' and state.get('unavailableEvents') == '0', 'Missing current system-unavailable callback'
    return 'PLATFORM_NO_RESPONSE'



def authenticate():
    wait_for(lambda tree: any(n.get('text') == 'Unlock Palladin' and
                             n.get('package') == 'com.android.systemui' for n in tree),
             'Real biometric prompt not shown')
    command('emu', 'finger', 'touch', '1')
    command('emu', 'finger', 'remove')
    if args.mode.startswith('native'):
        assert tap_text('Synthetic fixture'), 'Authenticated native picker missing'
        if args.mode == 'native-username-manual-cancel':
            assert tap_text('^Cancel$'), 'Explicit cancellation missing'
        elif 'manual' in args.mode:
            assert tap_text('^Fill username once$'), 'Explicit username-only confirmation missing'
        else:
            assert tap_text('Fill once'), 'Explicit manual warning missing'


def framework_snapshot(diagnosis):
    # AOSP API 35 Session.dumpLocked scalar fields only; never copy responses,
    # field values, dataset IDs or arbitrary framework text into artifacts.
    patterns = {
        'state': r'STATE_(?:UNKNOWN|ACTIVE|FINISHED|REMOVED)',
        'mResponses': r'(?:null|[0-9]{1,4})',
        'mDestroyed': r'(?:true|false)',
        'mShowingSaveUi': r'(?:true|false)',
        'mHasCallback': r'(?:true|false)',
        'mViewStates size': r'[0-9]{1,4}',
    }
    result = {}
    for line in diagnosis.splitlines():
        key, separator, value = line.strip().partition(': ')
        if separator and key in patterns and re.fullmatch(patterns[key], value):
            values = result.setdefault(key, [])
            if len(values) < 8:
                values.append(value)
    return result


def collect_inspector_failure(destination):
    if not args.inspect_response:
        return
    report = {}
    try:
        raw = command('shell', 'run-as', provider, 'cat', 'files/synthetic-failure.json')
        if len(raw) <= 16384:
            report['inspector'] = json.loads(raw)
    except Exception:
        pass
    try:
        command('shell', 'am', 'start', '-W', '-n', provider + '/io.palladin.mobile.MainActivity',
                '--ez', 'collectDiagnostics', 'true')
        raw = command('shell', 'run-as', provider, 'cat', 'files/synthetic-exits.json')
        if len(raw) <= 1024:
            report['exits'] = json.loads(raw)
    except Exception:
        pass
    if report:
        (destination / 'inspector.json').write_text(json.dumps(report, indent=2) + '\n')


def record_failure():
    if os.environ.get('GITHUB_ACTIONS') != 'true':
        return
    destination = Path(__file__).resolve().parent / 'build/exercise' / (
        args.mode + ('-response' if args.inspect_response else '-handoff'))
    destination.mkdir(parents=True, exist_ok=True)
    try:
        framework = framework_snapshot(command('shell', 'dumpsys', 'autofill'))
        framework['selectedSyntheticProvider'] = command(
            'shell', 'settings', 'get', 'secure', 'autofill_service').strip() == service
        (destination / 'framework.json').write_text(json.dumps(framework, indent=2) + '\n')
    except Exception:
        pass
    try:
        diagnosis = command('shell', 'dumpsys', 'activity', 'service', service)
        snapshot = request_snapshot(diagnosis)
        (destination / 'request.json').write_text(json.dumps(snapshot, indent=2) + '\n')
    except Exception:
        pass
    try:
        screenshot = subprocess.check_output(
            [adb, '-s', args.serial, 'exec-out', 'screencap', '-p'], timeout=15)
        (destination / 'screen.png').write_bytes(screenshot)
    except Exception:
        pass  # Diagnostic failure must not replace the original assertion.
    try:
        roles = {
            'Unlock Palladin to autofill': 'unlock-suggestion',
            'Unlock Palladin': 'biometric-title',
            'Synthetic fixture': 'synthetic-picker',
            'Fill once': 'manual-confirmation',
            'synthetic-user': 'synthetic-dataset',
            'Request Autofill': 'request-control',
            'Verify fill': 'verify-control',
            'fillVerified=true': 'fill-verified',
        }
        metadata = []
        for node in nodes()[:500]:
            item = {key: node.get(key) for key in (
                'package', 'class', 'resource-id', 'bounds', 'enabled', 'focused',
                'focusable', 'clickable', 'password')}
            item['role'] = roles.get(node.get('text'), roles.get(node.get('content-desc'), 'other'))
            metadata.append(item)
        (destination / 'nodes.json').write_text(json.dumps(metadata, indent=2) + '\n')
    except Exception:
        pass
    try:
        collect_inspector_failure(destination)
    except Exception:
        pass  # Keep the original failure even if artifact storage fails.


try:
    command('shell', 'pm', 'set-app-links', '--package', form, '2' if args.mode.startswith('web') or args.mode == 'native-username-manual-verified' else '0', 'fixture.invalid')
    command('shell', 'am', 'force-stop', form)
    command('shell', 'am', 'force-stop', provider)
    if args.inspect_response:
        if args.mode not in ('native-login', 'native-username', 'web-login', 'web-username', 'web-http', 'web-missing', 'web-empty', 'native-empty', 'native-username-manual', 'native-username-manual-verified', 'native-username-manual-password', 'web-username-manual', 'native-username-manual-cancel'):
            raise RuntimeError('Response inspection uses the four credential fixtures')
        prior_policy = command('shell', 'settings', 'get', 'global', 'hidden_api_policy').strip()
        try:
            command('shell', 'settings', 'put', 'global', 'hidden_api_policy', '1')
            command('shell', 'am', 'start', '-n', provider + '/io.palladin.mobile.MainActivity', '--es', 'inspectResponse', args.mode, '--es', 'inlineMode', args.inline_mode)
            if args.mode in ('web-http', 'web-missing', 'native-username-manual-password', 'web-username-manual'):
                wait_for(lambda tree: any(n.get('text') == 'responseRejected=true' for n in tree),
                         'Invalid scheme rejection result not observed')
                print(args.mode + ': no authentication result PASS')
            else:
                authenticate()
                expected_result = 'responseRejected=true' if args.mode.endswith(('empty', 'cancel')) else 'responseVerified=true'
                wait_for(lambda tree: any(n.get('text') == expected_result for n in tree),
                         'Actual FillResponse field ID/value assertions failed')
                print(args.mode + ': actual FillResponse dataset assertions PASS')
        finally:
            if prior_policy == 'null':
                command('shell', 'settings', 'delete', 'global', 'hidden_api_policy')
            else:
                command('shell', 'settings', 'put', 'global', 'hidden_api_policy', prior_policy)

    else:
        # /proc/uptime has 10ms precision; reject sessions inside that ambiguous tick.
        case_started_ms = None
        if args.mode.startswith('native'):
            case_started_ms = math.ceil(float(command('shell', 'cat', '/proc/uptime').split()[0]) * 1000) + 10
        command('shell', 'am', 'start', '-n', form + '/io.palladin.autofill.form.FormActivity', '--es', 'mode', args.mode)
        positive = args.mode in ('native-login', 'native-username', 'native-username-hint', 'native-login-opaque', 'native-username-manual', 'native-username-manual-verified', 'web-login', 'web-username')
        focus_field(required=positive)
        if not positive or args.mode in ('native-username-manual', 'native-username-manual-verified'):
            if args.mode.startswith('web'):
                wait_for(lambda tree: any(node.get('package') == form and 'domReady=true' in node.get('text', '').split() for node in tree),
                         'Web fixture DOM did not become ready')
            assert tap_text('Request Autofill'), 'Manual request control missing'
        diagnosis = ''
        for _ in range(30):
            diagnosis = command('shell', 'dumpsys', 'activity', 'service', service)
            if re.search(r'result=(RESPONSE_OFFERED|REJECTED)', diagnosis):
                break
            time.sleep(.1)
        if not positive:
            assert args.expected in ('REJECTED', 'NO_RESPONSE')
            observations = []
            for observation in range(2):
                if observation:
                    time.sleep(.5)
                    diagnosis = command('shell', 'dumpsys', 'activity', 'service', service)
                assert tap_text('Verify fill'), 'Fixture verification control missing'
                wait_for(lambda tree: any(node.get('package') == form and node.get('text') == 'fieldsUnchanged=true' for node in tree),
                         'Negative fixture fields were not empty')
                selected = command('shell', 'settings', 'get', 'secure', 'autofill_service').strip()
                null_password = False
                if args.mode.startswith('native') and request_snapshot(diagnosis).get('result') != 'REJECTED':
                    from null_response import password_null_response
                    null_password = password_null_response(
                        command('shell', 'dumpsys', 'autofill'),
                        api=int(command('shell', 'getprop', 'ro.build.version.sdk').strip()),
                        started_ms=case_started_ms, form=form, provider=provider,
                    )
                observations.append(negative_outcome(diagnosis, nodes(), selected, args.mode,
                                                     password_null=null_password))
            outcome = next((value for value in ('REJECTED', 'SYSTEM_UNAVAILABLE', 'SYSTEM_NULL_PASSWORD', 'PLATFORM_NO_RESPONSE', 'PLATFORM_INELIGIBLE') if value in observations))
        else:
            assert 'result=' + args.expected in diagnosis, 'Unexpected provider outcome: ' + diagnosis
            outcome = args.expected
        print(args.mode + ': ' + outcome)
        if args.fill:
            assert args.expected == 'RESPONSE_OFFERED'
            if args.mode.startswith('web'):
                assert_web_origin(diagnosis)
                print(args.mode + ': reported single verified web domain PASS')
            if not tap_text('Unlock Palladin to autofill'):
                # The public fixture button issues AutofillManager.requestAutofill,
                # which can expose the dropdown when the IME ignores inline UI.
                assert tap_text('Request Autofill'), 'Manual request control missing'
                assert tap_text('Unlock Palladin to autofill'), 'Accessible unlock suggestion missing'
            authenticate()
            assert tap_text('^synthetic-user$'), 'Authenticated dataset missing'
            assert tap_text('Verify fill'), 'Fixture verification control missing'
            wait_for(lambda tree: any(n.get('text') == 'fillVerified=true' for n in tree),
                     'Synthetic field assertions failed')
            print(args.mode + ': biometric + selection + field assertions PASS')
except Exception:
    record_failure()
    raise
