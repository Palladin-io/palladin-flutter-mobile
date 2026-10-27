import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_save_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('autofill-save-test');
  late List<String> calls;
  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return switch (call.method) {
            'activate' => 'original-session',
            'pending' => 'request',
            'take' => {
              'id': 'request',
              'packageName': 'synthetic.package',
              'mode': 'WEB',
              'domains': ['login.example.com'],
              'username': 'synthetic-user',
              'password': 'synthetic-password',
              'remainingMs': 60000,
            },
            'validate' => true,
            _ => null,
          };
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  test(
    'locked original account retains authority without consuming plaintext',
    () async {
      final controller = AutoFillSaveController(channel: channel);
      addTearDown(controller.dispose);
      await controller.synchronize('account', unlocked: true);
      controller.cancel();
      calls.clear();
      await controller.synchronize('account', unlocked: false);
      await controller.poll();
      expect(calls, isNot(contains('take')));
      expect(calls, isNot(contains('activate')));
      await controller.synchronize('account', unlocked: true);
      expect(controller.draft?.username, 'synthetic-user');
    },
  );

  test(
    'lock and account replacement discard already presented plaintext',
    () async {
      final controller = AutoFillSaveController(channel: channel);
      addTearDown(controller.dispose);
      await controller.synchronize('account', unlocked: true);
      final draft = controller.draft!;
      await controller.synchronize('account', unlocked: false);
      expect(draft.valid, false);
      expect(draft.password, isEmpty);
      await controller.synchronize(null, unlocked: false);
      expect(calls, contains('revoke'));
      expect(controller.draft, isNull);
    },
  );
  for (final transition in ['cancel', 'lock-unlock', 'background']) {
    test('delayed take cannot present after $transition', () async {
      var pending = false;
      final taken = Completer<Map<String, Object>>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (call) async => switch (call.method) {
              'activate' => 'session',
              'pending' => pending ? 'request' : null,
              'take' => taken.future,
              _ => null,
            },
          );
      final controller = AutoFillSaveController(channel: channel);
      addTearDown(controller.dispose);
      await controller.synchronize('account', unlocked: true);
      pending = true;
      final polling = controller.poll();
      await Future<void>.delayed(Duration.zero);
      if (transition == 'lock-unlock') {
        await controller.synchronize('account', unlocked: false);
        await controller.synchronize('account', unlocked: true);
      } else if (transition == 'background') {
        controller.background();
      } else {
        controller.cancel();
      }
      taken.complete({
        'id': 'request',
        'packageName': 'synthetic.package',
        'mode': 'WEB',
        'domains': ['login.example.com'],
        'username': 'synthetic-user',
        'password': 'synthetic-password',
        'remainingMs': 60000,
      });
      await polling;
      expect(controller.draft, isNull);
    });
  }
}
