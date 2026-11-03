import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_cache_bridge.dart';
import 'package:mobile_palladin/features/autofill/domain/autofill_incremental.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('autofill-v3-test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'native base is parsed strictly and never inferred from an empty response',
    () {
      expect(
        AutoFillCacheBase.fromPlatform({
          'generation': 7,
          'revision': 2,
        }).toPlatformMap(),
        {'generation': 7, 'revision': 2},
      );
      for (final invalid in [
        null,
        {},
        {'generation': 7},
        {'generation': 7, 'revision': 0},
        {'generation': '7', 'revision': 2},
      ]) {
        expect(
          () => AutoFillCacheBase.fromPlatform(invalid),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'writer epoch invalidation crosses native channel independently',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'beginWriterSession' ? 4 : null;
      });
      final bridge = MethodChannelAutoFillCacheBridge(
        channel: channel,
        availabilityProbe: () async => true,
      );
      expect(await bridge.beginWriterSession(sessionToken: 7), 4);
      await bridge.endWriterSession(writerEpoch: 4);
      expect(calls.map((call) => call.method), [
        'beginWriterSession',
        'endWriterSession',
      ]);
      expect(calls.last.arguments, {'writerEpoch': 4});
    },
  );

  test(
    'denial carries exact acknowledged base and returns native ownership',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'denyEntries');
        expect(call.arguments, {
          'base': {'generation': 7, 'revision': 2},
          'writerEpoch': 4,
          'entries': [
            {'vaultId': 'vault', 'entryId': 'entry'},
          ],
        });
        return {
          'base': {'generation': 7, 'revision': 3},
          'denyToken': 'native-owner',
        };
      });
      final bridge = MethodChannelAutoFillCacheBridge(
        channel: channel,
        availabilityProbe: () async => true,
      );
      final denied = await bridge.denyEntries(
        base: const AutoFillCacheBase(generation: 7, revision: 2),
        writerEpoch: 4,
        entries: const [
          AutoFillEntryCoordinate(vaultId: 'vault', entryId: 'entry'),
        ],
      );
      expect(denied.base.revision, 3);
      expect(denied.token, 'native-owner');
    },
  );
}
