import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/core/crypto/sodium_provider.dart';
import 'package:sodium/sodium_sumo.dart' as sodium_ffi;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../tool/member-preparation-benchmark/main.dart' as benchmark;

void main() {
  for (final entriesPerVault in [20, 128]) {
    final entryCount = 8 * entriesPerVault;
    test(
      '$entryCount entries: warm preparation and offline selected-only reveal',
      () async {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
        SodiumProvider.debugOverride = await sodium_ffi.SodiumSumoInit.init(
          () => DynamicLibrary.open(
            Platform.environment['PALLADIN_LIBSODIUM_PATH'] ?? 'libsodium.so',
          ),
        );
        try {
          final results = await benchmark.runBenchmark(
            repetitions: 1,
            entriesPerVault: entriesPerVault,
          );
          expect(results, hasLength(7));
          expect(
            results.take(4).every((row) => row['entries'] == entryCount),
            isTrue,
          );
          for (final cold in results.take(4)) {
            expect(cold['requests'], {
              'list': 1,
              'snapshot': entriesPerVault == 20 ? 8 : 16,
              'delta': 8,
            });
          }
          final selected = results.singleWhere(
            (row) => row['mode'] == 'shared-source',
          );
          for (final mode in ['warm-repeat', 'warm-repeat-slow']) {
            final warm = results.singleWhere((row) => row['mode'] == mode);
            expect(warm['entries'], entryCount);
            expect(warm['requests'], {'list': 1, 'delta': 8});
            expect(warm['vaultKeyOpens'], 8);
            expect(warm['indexOpens'], 0);
            expect(warm['secretOpens'], 0);
            expect(warm['requestDelayMillis'], mode.endsWith('slow') ? 25 : 0);
          }
          expect(selected['networkOffline'], isTrue);
          expect(selected['candidateIndexOpens'], 0);
          expect(selected['candidateVaultKeyOpens'], 0);
          expect(selected['candidates'], entryCount);
          expect(selected['candidateSecretReads'], 0);
          expect(selected['selectedSecretReads'], 1);
          expect(selected['selectedEntryReads'], 1);
          expect(selected['onlySelectedEntryRead'], isTrue);
          expect(selected['httpRequests'], 0);
          expect(selected['credentialVerified'], isTrue);
        } finally {
          SodiumProvider.debugOverride = null;
        }
      },
    );
  }
}
