import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_source_access_service.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_cache_bridge.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_source_invalidator.dart';

class _Legacy extends Mock implements AutoFillCacheBridge {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/source-retire');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  test(
    'source denial precedes legacy retirement without ending cleanup session',
    () async {
      final source = AutoFillSourceAccessService(channel: channel);
      final legacy = _Legacy();
      final events = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        events.add(call.method);
        return call.method == 'sourceSnapshot'
            ? {'sourceEpoch': 1, 'profileDigest': 'synthetic'}
            : 2;
      });
      when(legacy.revokeCacheAccess).thenAnswer((_) async {
        events.add('legacy');
        return 7;
      });
      when(() => legacy.clearCache(sessionToken: 7)).thenAnswer((_) async {
        events.add('clear');
      });
      final invalidator = AutoFillSourceInvalidator(
        source: source,
        legacy: legacy,
      );
      await invalidator.revokeAccess();
      await invalidator.clear();
      expect(events, ['sourceSnapshot', 'revokeSource', 'legacy', 'clear']);
    },
  );
  test('failed source deny cannot claim cleanup success', () async {
    final source = AutoFillSourceAccessService(channel: channel);
    final legacy = _Legacy();
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'unavailable');
    });
    final invalidator = AutoFillSourceInvalidator(
      source: source,
      legacy: legacy,
    );
    await expectLater(invalidator.clear(), throwsA(isA<PlatformException>()));
    verifyNever(legacy.revokeCacheAccess);
  });
  test(
    'unsupported platform logout does not invoke absent native providers',
    () async {
      final legacy = _Legacy();
      final invalidator = AutoFillSourceInvalidator(
        source: AutoFillSourceAccessService(channel: channel),
        legacy: legacy,
        supported: false,
      );
      await invalidator.revokeAccess();
      await invalidator.clear();
      await invalidator.retireLegacy();
      verifyZeroInteractions(legacy);
    },
  );
}
