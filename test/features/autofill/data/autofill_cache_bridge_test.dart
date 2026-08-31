import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_cache_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('io.palladin.mobile/autofill-test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'unsupported iOS simulator is reported as a missing native plugin',
    () async {
      var nativeCalls = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        nativeCalls++;
        return 1;
      });
      final bridge = MethodChannelAutoFillCacheBridge(
        channel: channel,
        availabilityProbe: () async => false,
      );

      await expectLater(
        bridge.beginCacheSession(),
        throwsA(isA<MissingPluginException>()),
      );

      expect(nativeCalls, 0);
    },
  );

  test('supported device still propagates native platform failures', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'AUTOFILL_CACHE_ERROR');
    });
    final bridge = MethodChannelAutoFillCacheBridge(
      channel: channel,
      availabilityProbe: () async => true,
    );

    await expectLater(
      bridge.beginCacheSession(),
      throwsA(isA<PlatformException>()),
    );
  });
}
