import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/config/env_config.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_sharing/entry_share_ingress.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_sharing/entry_share_link_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('io.palladin.mobile/entry-sharing');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final initial = DateTime.utc(2026, 9, 21);
  const id = '00112233-4455-4677-8899-aabbccddeeff';
  final fragment = '#v=1&key=${'A' * 42}E&access=${'A' * 42}I';
  final url = 'https://stage.palladin.io/share/$id$fragment';
  late EntryShareIngress ingress;
  late DateTime now;
  late Duration elapsed;
  late Future<Object?> Function() response;
  late int calls;

  Map<String, Object?> message(int generation, {String? link, int age = 0}) => {
    'generation': generation,
    'url': link ?? url,
    'receivedAtUnixMs': initial.millisecondsSinceEpoch,
    'ageMilliseconds': age,
  };
  Future<void> announce(Object? generation) async {
    final done = Completer<void>();
    messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(MethodCall('pending', generation)),
      (_) => done.complete(),
    );
    await done.future;
    await Future<void>.delayed(Duration.zero);
  }

  setUp(() {
    now = initial;
    elapsed = Duration.zero;
    calls = 0;
    response = () async => null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'takePending');
      expect(call.arguments, isNull);
      calls++;
      return response();
    });
    ingress = EntryShareIngress(
      links: EntryShareLinkService(
        EnvConfig.staging(sharingWebOrigin: 'https://stage.palladin.io'),
      ),
      now: () => now,
      elapsed: () => elapsed,
    );
  });
  tearDown(() {
    ingress.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'cold ingress takes one RAM capability without routing or network',
    () async {
      response = () async => message(1);
      await ingress.start();
      expect(ingress.hasPending, true);
      final pending = ingress.take(ingress.version)!;
      expect(pending.shareId, id);
      expect(pending.secrets.toFragment(), fragment);
      expect(ingress.hasPending, false);
      expect(ingress.take(ingress.version), isNull);
      pending.secrets.dispose();
      await ingress.start();
      expect(calls, 1);
    },
  );
  test(
    'pending lifetime includes native age, channel wait and auth wait',
    () async {
      final result = Completer<Object?>();
      response = () => result.future;
      final start = ingress.start();
      elapsed = const Duration(minutes: 2);
      result.complete(
        message(1, age: const Duration(minutes: 3).inMilliseconds),
      );
      await start;
      elapsed += const Duration(minutes: 4);
      final pending = ingress.take(ingress.version)!;
      expect(pending.lifetime.remaining, const Duration(minutes: 6));
      pending.secrets.dispose();
    },
  );
  test(
    'warm replacement notifies invalidation before its payload arrives',
    () async {
      response = () async => message(1);
      await ingress.start();
      final oldVersion = ingress.version;
      final next = Completer<Object?>();
      response = () => next.future;
      var invalidations = 0;
      ingress.addListener(() {
        if (!ingress.hasPending) invalidations++;
      });
      await announce(2);
      expect(ingress.hasPending, false);
      expect(ingress.take(oldVersion), isNull);
      expect(invalidations, 1);
      next.complete(message(2));
      await Future<void>.delayed(Duration.zero);
      final pending = ingress.take(ingress.version)!;
      pending.secrets.dispose();
    },
  );
  test(
    'older native completion cannot replace the newer announcement',
    () async {
      final first = Completer<Object?>();
      final second = Completer<Object?>();
      response = () => calls == 1 ? first.future : second.future;
      final start = ingress.start();
      await announce(2);
      first.complete(message(1));
      await Future<void>.delayed(Duration.zero);
      expect(ingress.hasPending, false);
      second.complete(message(2));
      await start;
      expect(calls, 2);
      final pending = ingress.take(ingress.version)!;
      pending.secrets.dispose();
    },
  );
  test(
    'same-generation event during take does not lose the one-shot payload',
    () async {
      final result = Completer<Object?>();
      response = () => calls == 1 ? result.future : Future.value(null);
      final start = ingress.start();
      await announce(1);
      result.complete(message(1));
      await start;
      expect(ingress.hasPending, true);
      final pending = ingress.take(ingress.version)!;
      pending.secrets.dispose();
    },
  );
  test(
    'duplicate and older announcements cannot replay a consumed link',
    () async {
      response = () async => message(2);
      await ingress.start();
      final pending = ingress.take(ingress.version)!;
      pending.secrets.dispose();
      await announce(1);
      await announce(2);
      expect(calls, 1);
      expect(ingress.hasPending, false);
    },
  );
  test('clear while taking native payload fences the delayed reply', () async {
    final result = Completer<Object?>();
    response = () => result.future;
    final start = ingress.start();
    ingress.clear();
    result.complete(message(1));
    await start;
    expect(ingress.hasPending, false);
  });
  test(
    'dispose while taking cannot publish the delayed native payload',
    () async {
      final result = Completer<Object?>();
      response = () => result.future;
      final start = ingress.start();
      ingress.dispose();
      result.complete(message(1));
      await start;
      expect(ingress.take(ingress.version), isNull);
    },
  );
  test(
    'listener clear at invalidation cannot resurrect a capability',
    () async {
      void clearOnce() {
        ingress.removeListener(clearOnce);
        ingress.clear();
      }

      ingress.addListener(clearOnce);
      response = () async => message(1);
      await ingress.start();
      expect(ingress.hasPending, false);
    },
  );
  test('malformed replacement removes old pending material', () async {
    response = () async => message(1);
    await ingress.start();
    response = () async => message(2, link: '$url&unexpected=secret');
    await announce(2);
    expect(ingress.hasPending, false);
    expect(ingress.take(ingress.version), isNull);
  });
  test(
    'expired native response fails closed instead of starting a new TTL',
    () async {
      response = () async =>
          message(1, age: const Duration(minutes: 15).inMilliseconds);
      await ingress.start();
      expect(ingress.hasPending, false);
    },
  );
  test('take checks both clocks even if expiry callback has not run', () async {
    response = () async => message(1);
    await ingress.start();
    elapsed = const Duration(minutes: 15);
    expect(ingress.take(ingress.version), isNull);
    elapsed = Duration.zero;
    expect(ingress.take(ingress.version), isNull);
  });
  testWidgets('expiry timer invalidates an unclaimed pending capability', (
    tester,
  ) async {
    response = () async =>
        message(1, age: const Duration(minutes: 14).inMilliseconds);
    final start = ingress.start();
    await tester.pump();
    await start;
    expect(ingress.hasPending, true);
    await tester.pump(const Duration(minutes: 1));
    expect(ingress.hasPending, false);
  });
  test('malformed and exceptional native responses stay value-free', () async {
    response = () async => throw PlatformException(code: 'bad', message: url);
    await ingress.start();
    expect(ingress.hasPending, false);
    var generation = 0;
    for (final value in [
      {
        'url': url,
        'ageMilliseconds': -1,
        'receivedAtUnixMs': initial.millisecondsSinceEpoch,
      },
      {'url': url, 'ageMilliseconds': 0, 'receivedAtUnixMs': 'invalid'},
      {
        'url': url,
        'ageMilliseconds': 0,
        'receivedAtUnixMs': 9223372036854775807,
      },
    ]) {
      generation++;
      response = () async => {'generation': generation, ...value};
      await announce(generation);
      expect(ingress.hasPending, false);
    }
  });
}
