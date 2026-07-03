import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/core/utils/secure_clipboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  String? clip;

  setUp(() {
    clip = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      switch (call.method) {
        case 'Clipboard.setData':
          clip = (call.arguments as Map)['text'] as String?;
          return null;
        case 'Clipboard.getData':
          return <String, dynamic>{'text': clip};
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test('copies the value then wipes it after the delay', () async {
    await SecureClipboard.copy(
      'super-secret',
      clearAfter: const Duration(milliseconds: 20),
    );
    expect(clip, 'super-secret');

    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(clip, '');
  });

  test('does not clobber a value the user copied afterwards', () async {
    await SecureClipboard.copy(
      'super-secret',
      clearAfter: const Duration(milliseconds: 20),
    );
    // Simulate the user copying something else before the wipe fires.
    clip = 'user-copied-this';

    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(clip, 'user-copied-this');
  });
}
