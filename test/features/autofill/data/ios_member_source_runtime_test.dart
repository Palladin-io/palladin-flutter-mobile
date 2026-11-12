import 'dart:io';
import 'dart:convert';
import 'dart:ffi';
import 'package:sodium/sodium_sumo.dart' as sodium_ffi;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mobile_palladin/core/crypto/sodium_provider.dart';
import 'package:mobile_palladin/features/unlock/data/services/identity_kdf_service.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_cache.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_v2_crypto_service.dart';
import 'package:mobile_palladin/features/vault/data/models/member_sync_models.dart';
import '../../../fixtures/autofill/ios_member_runtime_fixture.dart';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/autofill/data/ios_member_source_runtime.dart';

class _CountingCrypto extends EntryV2CryptoService {
  var bodyOpens = 0;
  @override
  Future<Map<String, dynamic>> openMemberSecret({
    required Map<String, dynamic> entryKey,
    required Map<String, dynamic> memberSecret,
    required Uint8List vaultKey,
  }) {
    bodyOpens++;
    return super.openMemberSecret(
      entryKey: entryKey,
      memberSecret: memberSecret,
      vaultKey: vaultKey,
    );
  }
}

void main() {
  for (final usePassword in [false, true]) {
    test(
      'real readonly SQLite ${usePassword ? 'password KDF' : 'biometric key with future-issued lease'} opens only selected body',
      () async {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
        final sodium = await sodium_ffi.SodiumSumoInit.init(
          () => DynamicLibrary.open(
            Platform.environment['PALLADIN_LIBSODIUM_PATH'] ??
                (Platform.isMacOS
                    ? '/opt/homebrew/lib/libsodium.dylib'
                    : 'libsodium.so'),
          ),
        );
        SodiumProvider.debugOverride = sodium;
        final directory = await Directory.systemTemp.createTemp(
          'palladin-extension-real-',
        );
        final databasePath = '${directory.path}/vault_member_sync.db';
        final db = await openDatabase(
          databasePath,
          version: 2,
          onCreate: (db, _) async {
            await db.execute(
              'CREATE TABLE member_sync_heads (vault_id TEXT NOT NULL,generation TEXT NOT NULL,entry_id TEXT NOT NULL,envelope_json TEXT NOT NULL,PRIMARY KEY(vault_id,generation,entry_id))',
            );
            await db.execute(
              'CREATE TABLE member_sync_state (vault_id TEXT PRIMARY KEY,applied_sequence TEXT NOT NULL,access_context_json TEXT NOT NULL,member_vault_key_json TEXT NOT NULL,maximum_observed_wall_micros INTEGER NOT NULL)',
            );
            await db.execute(
              'CREATE TABLE member_sync_profile_fence (singleton INTEGER PRIMARY KEY CHECK(singleton=1),generation INTEGER NOT NULL)',
            );
          },
        );
        IosMemberSourceRuntime? runtime;
        try {
          final fixture = jsonDecode(syntheticFixture) as Map<String, dynamic>;
          const vault = '22222222-2222-4222-8222-222222222222';
          const member = '44444444-4444-4444-8444-444444444444';
          const org = '11111111-1111-4111-8111-111111111111';
          final now = DateTime.now().toUtc();
          final issuedAt = usePassword
              ? now.subtract(const Duration(minutes: 1))
              : now.add(const Duration(minutes: 4));
          final wrapper = fixture['wrapper'] as Map<String, dynamic>;
          final context = MemberOfflineAccessContext(
            contextVersion: 1,
            principalId: member,
            organizationId: org,
            organizationMembershipGeneration: '1',
            vaultId: vault,
            memberId: member,
            memberKeyGeneration: 1,
            vaultKeyVersion: 1,
            memberRecipientKeyVersion: 1,
            memberRecipientKeyFingerprint:
                wrapper['wrappedVaultKey']['descriptor']['recipientFingerprint']
                    as String,
            offlinePolicy: '24h',
            offlinePolicyVersion: 1,
            issuedAt: issuedAt,
            notAfter: issuedAt.add(const Duration(hours: 24)),
          );
          final cache = SqliteMemberSyncCache(databaseLoader: () async => db);
          await cache.beginSnapshot(vault, invalidateActive: false);
          await cache.appendSnapshot(vault, [
            MemberSyncItemModel(
              entryId: '33333333-3333-4333-8333-333333333333',
              kind: 'head',
              state: 'active',
              updatedAt: now,
              currentRevision: '1',
              memberIndexRevision: '1',
              currentKeyVersion: 1,
              entryKey: fixture['entryKey'],
              memberIndex: fixture['memberIndex'],
              memberSecret: fixture['memberSecret'],
            ),
          ]);
          await cache.promoteSnapshot(
            vault,
            sequence: '1',
            accessContext: context,
            memberVaultKey: wrapper,
            maximumObservedWallTime: now,
          );
          final kdfSalt = Uint8List.fromList(List.filled(16, 6));
          final derived = await IdentityKdfService().derive(
            password: 'synthetic-master-password',
            accountId: member,
            kdfSalt: kdfSalt,
          );
          final master = Uint8List.fromList(derived.masterKey);
          derived.dispose();
          final secureMaster = sodium_ffi.SecureKey.fromList(sodium, master);
          final nonce = sodium.randombytes.buf(
            sodium.crypto.secretBox.nonceBytes,
          );
          final private = base64Decode(fixture['privateKey'] as String);
          final encryptedPrivateKey = base64Encode([
            ...nonce,
            ...sodium.crypto.secretBox.easy(
              message: private,
              nonce: nonce,
              key: secureMaster,
            ),
          ]);
          private.fillRange(0, private.length, 0);
          secureMaster.dispose();
          final crypto = _CountingCrypto();
          var completions = 0;
          Map<String, Object?> arguments() => {
            'databasePath': databasePath,
            if (usePassword)
              'masterPassword': 'synthetic-master-password'
            else
              'masterKey': master,
            'request': {
              'id': 'synthetic',
              'remainingMs': 60000,
              'mode': 'WEB',
              'verifiedHosts': ['example.invalid'],
              'usernameOnly': false,
            },
            'claims': {
              'principalId': member,
              'organizationId': org,
              'organizationMembershipGeneration': '1',
              'offlinePolicy': '24h',
              'offlinePolicyVersion': 1,
            },
            'accountUnlock': {
              'accountId': member,
              'encryptedPrivateKey': encryptedPrivateKey,
              'kdf': {
                'securityVersion': 1,
                'minimumSecurityVersion': 1,
                'profileId': IdentityKdfProfile.id,
                'kdfSalt': base64UrlEncode(kdfSalt).replaceAll('=', ''),
                'credentialRevision': 1,
                'privateKeyWrapRevision': 1,
              },
            },
          };
          if (usePassword) {
            await expectLater(
              IosMemberSourceRuntime.open(
                arguments: arguments()
                  ..['masterPassword'] = 'wrong-synthetic-password',
                validateNative: () async => true,
                completeNative: (_) async {
                  fail('wrong password handoff');
                },
                entryCrypto: crypto,
              ),
              throwsA(isA<IosMemberSourceException>()),
            );
            expect(crypto.bodyOpens, 0);
          }
          runtime = await IosMemberSourceRuntime.open(
            arguments: arguments(),
            validateNative: () async => true,
            entryCrypto: crypto,
            completeNative: (value) async {
              expect(value['username'], 'synthetic');
              expect(value['password'], 'synthetic-only');
              completions++;
            },
          );
          if (usePassword) master.fillRange(0, master.length, 0);
          expect(master, everyElement(0));
          final rows = await runtime.session.candidates();
          expect(rows, hasLength(1));
          expect(rows.single['label'], 'Synthetic');
          expect(crypto.bodyOpens, 0);
          if (!usePassword) {
            expect(DateTime.now().toUtc().isBefore(context.issuedAt), isTrue);
          }
          await runtime.session.select(
            selectionId: rows.single['selectionId'] as String,
            selectedHost: 'example.invalid',
            manualConfirmed: false,
          );
          expect(crypto.bodyOpens, 1);
          expect(completions, 1);
          expect((await db.query('member_sync_heads')), hasLength(1));
        } finally {
          await runtime?.close();
          await db.close();
          await directory.delete(recursive: true);
          SodiumProvider.debugOverride = null;
        }
      },
    );
  }
  test(
    'missing canonical DB is rejected without creating a file or opening a network',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'palladin-extension-runtime-',
      );
      final path = '${directory.path}/vault_member_sync.db';
      final key = Uint8List(32);
      try {
        await expectLater(
          IosMemberSourceRuntime.open(
            arguments: {
              'databasePath': path,
              'request': {
                'id': 'synthetic',
                'remainingMs': 60000,
                'mode': 'WEB',
                'verifiedHosts': ['example.invalid'],
                'usernameOnly': false,
              },
              'claims': {
                'principalId': 'synthetic',
                'organizationId': 'org',
                'organizationMembershipGeneration': '1',
                'offlinePolicy': '24h',
                'offlinePolicyVersion': 1,
              },
              'accountUnlock': {
                'accountId': 'synthetic',
                'encryptedPrivateKey': 'invalid',
                'kdf': {},
              },
              'masterKey': key,
            },
            validateNative: () async => true,
            completeNative: (_) async {
              fail('must not complete');
            },
          ),
          throwsA(isA<IosMemberSourceException>()),
        );
        expect(await File(path).exists(), isFalse);
        expect(key, everyElement(0));
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
  test(
    'native denial prevents even source database discovery and wipes incoming key',
    () async {
      final key = Uint8List.fromList(List.filled(32, 7));
      await expectLater(
        IosMemberSourceRuntime.open(
          arguments: {'masterKey': key},
          validateNative: () async => false,
          completeNative: (_) async {
            fail('must not complete');
          },
        ),
        throwsA(isA<IosMemberSourceException>()),
      );
      expect(key, everyElement(0));
    },
  );
}
