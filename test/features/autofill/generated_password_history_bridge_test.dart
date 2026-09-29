import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/autofill/data/generated_password_history_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/generated-password-history');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'generation returns only the password committed by native history',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'generatePasswordForEntry') {
          return 'A1!strong-generated-value';
        }
        return null;
      });
      final bridge = GeneratedPasswordHistoryBridge(channel: channel);

      final password = await bridge.generateForEntry(
        'principal-a',
        'example.com',
        biometricPrompt: 'Authenticate',
      );

      expect(password, 'A1!strong-generated-value');
      expect(calls.single.method, 'generatePasswordForEntry');
      expect(calls.single.arguments, {
        'principalId': 'principal-a',
        'domain': 'example.com',
        'prompt': 'Authenticate',
      });
    },
  );

  test(
    'native persistence failure cannot expose a generated password',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'AUTOFILL_CACHE_ERROR');
      });
      final bridge = GeneratedPasswordHistoryBridge(channel: channel);

      await expectLater(
        bridge.generateForEntry(
          'principal-a',
          'example.com',
          biometricPrompt: 'Authenticate',
        ),
        throwsA(isA<PlatformException>()),
      );
    },
  );

  test(
    'history summaries omit passwords; reveal is a separate operation',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'listGeneratedPasswords') {
          return [
            {
              'id': 'record-a',
              'domain': 'example.com',
              'createdAtMillis': 1000,
            },
          ];
        }
        if (call.method == 'revealGeneratedPassword') return 'secret';
        return null;
      });
      final bridge = GeneratedPasswordHistoryBridge(channel: channel);

      final list = await bridge.list(
        'principal-a',
        biometricPrompt: 'Authenticate',
      );
      expect(list.single.id, 'record-a');
      expect(list.single.domain, 'example.com');
      expect(calls.single.method, 'listGeneratedPasswords');

      final password = await bridge.reveal(
        'principal-a',
        'record-a',
        biometricPrompt: 'Authenticate',
      );
      expect(password, 'secret');
      expect(calls.last.arguments, {
        'principalId': 'principal-a',
        'id': 'record-a',
        'prompt': 'Authenticate',
      });
    },
  );
}
