import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sodium_libs/sodium_libs_sumo.dart';

const _password = 'Palladin deterministic KDF benchmark password';
final _salt = Uint8List.fromList(List<int>.generate(16, (index) => index + 1));

const _profiles = <({String id, int memoryKiB, int iterations})>[
  (id: 'identity-argon2id-legacy-v1', memoryKiB: 19456, iterations: 2),
  (id: 'identity-argon2id-account-secret-v2', memoryKiB: 47104, iterations: 1),
  (
    id: 'identity-argon2id-rfc9106-64m-v2-candidate',
    memoryKiB: 65536,
    iterations: 3,
  ),
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('records Argon2id latency and process memory', (tester) async {
    final sodium = await SodiumSumoInit.init();
    final password = Int8List.fromList(utf8.encode(_password));
    final results = <Map<String, Object>>[];

    for (final profile in _profiles) {
      final samples = <int>[];
      final rssBefore = ProcessInfo.currentRss;
      final maxRssBefore = ProcessInfo.maxRss;

      for (var run = 0; run < 6; run++) {
        final stopwatch = Stopwatch()..start();
        final key = sodium.crypto.pwhash.call(
          outLen: 32,
          password: password,
          salt: _salt,
          opsLimit: profile.iterations,
          memLimit: profile.memoryKiB * 1024,
          alg: CryptoPwhashAlgorithm.argon2id13,
        );
        stopwatch.stop();
        key.dispose();
        if (run > 0) samples.add(stopwatch.elapsedMicroseconds);
      }

      samples.sort();
      results.add({
        'profileId': profile.id,
        'memoryKiB': profile.memoryKiB,
        'iterations': profile.iterations,
        'parallelism': 1,
        'runs': samples.length,
        'medianMicros': samples[samples.length ~/ 2],
        'maxObservedMicros': samples.last,
        'rssBeforeBytes': rssBefore,
        'rssAfterBytes': ProcessInfo.currentRss,
        'maxRssBeforeBytes': maxRssBefore,
        'maxRssAfterBytes': ProcessInfo.maxRss,
      });
    }

    // One machine-readable line is copied verbatim into the CVT-396 evidence.
    // The input is synthetic and contains no user, credential or key material.
    // ignore: avoid_print
    print('KDF_BENCHMARK_JSON=${jsonEncode(results)}');
  });
}
