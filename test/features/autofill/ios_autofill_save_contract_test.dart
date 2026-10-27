import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_save_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'iOS HTTPS handoff carries biometric prompt and scoped cancellation',
    () async {
      const channel = MethodChannel('ios-autofill-save-contract');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return switch (call.method) {
              'activate' => 'synthetic-session',
              'pending' => 'synthetic-capture',
              'take' => {
                'id': 'synthetic-capture',
                'mode': 'IOS_HTTPS',
                'packageName': '',
                'sourceLabel': 'login.example.test',
                'domains': ['login.example.test'],
                'username': 'synthetic-user',
                'password': 'synthetic-password',
                'remainingMs': 60000,
              },
              'validate' => true,
              _ => null,
            };
          });
      final controller = AutoFillSaveController(channel: channel)
        ..biometricPrompt = () => 'Synthetic biometric prompt';
      addTearDown(() {
        controller.dispose();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      await controller.synchronize('synthetic-principal', unlocked: true);
      final draft = controller.draft!;
      expect(draft.isWeb, isTrue);
      expect(draft.packageName, isEmpty);
      expect(draft.sourceLabel, 'login.example.test');
      expect(draft.domains, ['login.example.test']);
      expect(calls.singleWhere((call) => call.method == 'take').arguments, {
        'id': 'synthetic-capture',
        'session': 'synthetic-session',
        'prompt': 'Synthetic biometric prompt',
      });
      expect(await controller.validate(draft, draft.domains.single), isTrue);
      expect(calls.last.arguments, {
        'id': 'synthetic-capture',
        'session': 'synthetic-session',
        'domain': 'login.example.test',
      });
      controller.cancelDraft(draft);
      await Future<void>.delayed(Duration.zero);
      expect(calls.last.method, 'cancel');
      expect(calls.last.arguments, {'id': 'synthetic-capture'});
      expect(draft.password, isEmpty);
    },
  );
}
