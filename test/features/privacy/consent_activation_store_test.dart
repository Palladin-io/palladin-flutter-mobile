import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/privacy/data/consent_activation_store.dart';

void main() {
  late Directory cache;
  late ConsentActivationStore store;
  setUp(() async {
    cache = await Directory.systemTemp.createTemp('palladin-consent-store-');
    store = ConsentActivationStore(cacheDirectory: () async => cache);
  });
  tearDown(() async => cache.delete(recursive: true));

  test(
    'activation survives process restart only for its account and is removable',
    () async {
      await store.write('account', const ConsentActivation('test-v1', 3));
      final restarted = ConsentActivationStore(
        cacheDirectory: () async => cache,
      );
      expect((await restarted.read('account'))?.revision, 3);
      expect(await restarted.read('other'), isNull);
      await restarted.write('account', null);
      expect(await store.read('account'), isNull);
    },
  );

  test(
    'fresh installation or purged cache never restores an account activation',
    () async {
      await store.write('account', const ConsentActivation('test-v1', 3));
      final freshCache = await cache.createTemp('new-installation-');
      final fresh = ConsentActivationStore(
        cacheDirectory: () async => freshCache,
      );
      expect(await fresh.read('account'), isNull);
      await Directory(
        '${cache.path}/consent-activation',
      ).delete(recursive: true);
      expect(await store.read('account'), isNull);
    },
  );

  test(
    'unsafe filename characters stay inside the cache and corrupt state fails closed',
    () async {
      await store.write('../../other', const ConsentActivation('test-v1', 1));
      final files = await Directory(
        '${cache.path}/consent-activation',
      ).list().toList();
      expect(files, hasLength(1));
      expect(files.single.parent.path, '${cache.path}/consent-activation');
      await File(files.single.path).writeAsString('{partial');
      expect(await store.read('../../other'), isNull);
    },
  );
}
