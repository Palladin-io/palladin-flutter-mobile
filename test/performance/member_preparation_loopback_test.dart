import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/core/crypto/sodium_provider.dart';
import 'package:sodium/sodium_sumo.dart' as sodium_ffi;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../tool/member-preparation-benchmark/main.dart' as benchmark;

void main() {
  test(
    'real loopback, crypto and SQLite preserve batched request count',
    () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      SodiumProvider.debugOverride = await sodium_ffi.SodiumSumoInit.init(
        () => DynamicLibrary.open(
          Platform.environment['PALLADIN_LIBSODIUM_PATH'] ?? 'libsodium.so',
        ),
      );
      try {
        final results = await benchmark.runBenchmark(repetitions: 1);
        expect(results, hasLength(4));
        expect(results.every((result) => result['entries'] == 160), isTrue);
      } finally {
        SodiumProvider.debugOverride = null;
      }
    },
  );
}
