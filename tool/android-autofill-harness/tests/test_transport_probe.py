import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


class TransportProbeTests(unittest.TestCase):
    def test_first_case_failure_is_preserved_and_other_fresh_renderer_runs_once(self):
        report, launched = self.execute(fail_first=True)
        self.assertEqual(launched, ['software', 'swiftshader'])
        self.assertEqual([r['passedCases'] for r in report['results']], [0, 10])
        self.assertEqual(report['results'][0]['failureStage'], '1-web-login')
        self.assertEqual(report['results'][0]['failureExit'], 7)
        self.assertFalse(report['comparisonPassed'])
        self.assertEqual(report['purpose'], 'TRANSPORT_PROBE_NOT_ACCEPTANCE')

    def test_success_is_only_probe_evidence_for_identical_apks(self):
        report, launched = self.execute(fail_first=False)
        self.assertEqual(launched, ['software', 'swiftshader'])
        self.assertEqual([r['passedCases'] for r in report['results']], [10, 10])
        self.assertTrue(report['sourceClean'])
        self.assertTrue(report['comparisonPassed'])
        self.assertEqual(set(report['apkSha256']), {'provider', 'form'})

    def test_single_boot_transport_delay_uses_existing_boot_deadline(self):
        report, launched = self.execute(fail_first=False, boot_timeout_once=True)
        self.assertTrue(report['comparisonPassed'])
        self.assertEqual(launched, ['software', 'swiftshader'])

    def execute(self, fail_first, boot_timeout_once=False):
        script = Path(__file__).resolve().parents[1] / 'transport_probe.py'
        spec = importlib.util.spec_from_file_location('transport_probe', script)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        launched = []
        processes = []
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            here = root / 'tool/harness'
            sdk = root / 'sdk'
            for path in [here / f'{m}/build/outputs/apk/debug/{m}-debug.apk' for m in ('provider', 'form')] + [sdk / 'emulator/emulator', sdk / 'system-images/android-35/google_apis/x86_64/system.img']:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b'fixed-synthetic-artifact')
            module.ROOT, module.HERE = root, here
            class Process:
                def __init__(self, command, **kwargs):
                    if processes:
                        self_test.assertIsNotNone(processes[-1].poll())
                    launched.append(command[command.index('-gpu') + 1])
                    self.code = None
                    processes.append(self)
                def poll(self): return self.code
                def terminate(self): self.code = 0
                def kill(self): self.code = -9
                def wait(self, timeout): return self.code
            self_test = self
            def output(command, **kwargs):
                if command[:2] == ['git', 'rev-parse']: return 'a' * 40
                if command[-1] == '-version': return 'Android emulator test'
                if command[-1] == 'get_sync_disabled_for_tests': return 'until_reboot'
                return ''
            boot_delayed = False
            def run(command, **kwargs):
                nonlocal boot_delayed
                if boot_timeout_once and not boot_delayed and command[-1] == 'sys.boot_completed':
                    boot_delayed = True
                    raise subprocess.TimeoutExpired(command, 5)
                if 'exercise.py' in ' '.join(command) and fail_first and launched[-1] == 'software':
                    raise subprocess.CalledProcessError(7, command)
                value = '1' if kwargs.get('text') else b'1'
                return subprocess.CompletedProcess(command, 0, stdout=value, stderr='')
            with patch.dict(os.environ, {'GITHUB_ACTIONS': 'true', 'RUNNER_TEMP': directory, 'ANDROID_HOME': str(sdk)}), patch.object(sys, 'argv', ['probe', '--gradle', 'gradle']), patch.object(module.subprocess, 'run', side_effect=run), patch.object(module.subprocess, 'check_output', side_effect=output), patch.object(module.subprocess, 'Popen', Process), patch.object(module.time, 'sleep'):
                if fail_first:
                    with self.assertRaises(SystemExit) as error: module.main()
                    self.assertEqual(error.exception.code, 1)
                else:
                    module.main()
            self.assertFalse((here / 'build/validation.json').exists())
            self.assertEqual(list(root.glob('palladin-renderer-*')), [])
            return json.loads((here / 'build/transport-probe/probe.json').read_text()), launched
