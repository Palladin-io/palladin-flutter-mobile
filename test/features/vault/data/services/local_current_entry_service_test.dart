import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mobile_palladin/core/storage/secure_token_storage.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/vault/data/models/member_sync_models.dart';
import 'package:mobile_palladin/features/vault/data/services/canonical_entry_detail_service.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_v2_crypto_service.dart';
import 'package:mobile_palladin/features/vault/data/services/local_current_entry_service.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_service.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_session_authority_provider.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_rotation_crypto_service.dart';

class _MockReader extends Mock implements LocalMemberEntryReader {}

class _MockAuthorityProvider extends Mock
    implements MemberSyncSessionAuthorityProvider {}

class _MockVaultKeys extends Mock implements VaultRotationCryptoService {}

class _MockEntryCrypto extends Mock implements EntryV2CryptoService {}

class _MockCanonicalAdapter extends Mock
    implements CanonicalEntryDetailService {}

class _NativeStorage extends Mock implements FlutterSecureStorage {}

class _PreparationProvider extends MemberSyncSessionAuthorityProvider {
  _PreparationProvider(super.storage, this.claims);
  final MemberSyncSessionAuthority claims;
  @override
  Future<MemberSyncSessionAuthority> current() async => claims;
}

void main() {
  setUpAll(() {
    registerFallbackValue(Uint8List(32));
    registerFallbackValue(<String, dynamic>{});
  });

  test(
    'preparation authority owner and mid-read mutation fail before crypto',
    () async {
      final native = _NativeStorage();
      when(() => native.deleteAll()).thenAnswer((_) async {});
      final storage = SecureTokenStorage(native);
      const claims = MemberSyncSessionAuthority(
        principalId: 'member',
        organizationId: 'org',
        organizationMembershipGeneration: '1',
        offlinePolicy: '24h',
        offlinePolicyVersion: 1,
      );
      final provider = _PreparationProvider(storage, claims);
      final reader = _MockReader();
      final keys = _MockVaultKeys();
      final service = LocalCurrentEntryService(
        reader: reader,
        authorityProvider: provider,
        vaultKeys: keys,
        entryCrypto: _MockEntryCrypto(),
        canonicalAdapter: _MockCanonicalAdapter(),
      );
      final other = await _PreparationProvider(
        storage,
        claims,
      ).captureForPreparation();
      await expectLater(
        service.revealPreparedWithAuthority(
          vaultId: 'vault',
          entryId: 'entry',
          memberPrivateKey: Uint8List(32),
          authority: other,
        ),
        throwsStateError,
      );
      verifyZeroInteractions(reader);
      final scope = await provider.captureForPreparation();
      final read = Completer<LocalMemberEntryMaterial?>();
      when(
        () => reader.readCurrent(
          vaultId: 'vault',
          entryId: 'entry',
          authority: claims,
        ),
      ).thenAnswer((_) => read.future);
      final pending = service.revealPreparedWithAuthority(
        vaultId: 'vault',
        entryId: 'entry',
        memberPrivateKey: Uint8List(32),
        authority: scope,
      );
      final rejected = expectLater(pending, throwsStateError);
      await storage.clearAll();
      read.complete(null);
      await rejected;
      verifyZeroInteractions(keys);
    },
  );

  test(
    'lock fence rejects a decryption that completes after local read',
    () async {
      final fixture =
          jsonDecode(
                File(
                  'test/fixtures/current_member_entry_sync_v2/valid-snapshot.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final snapshot = MemberSnapshotPage.fromJson(
        Map<String, dynamic>.from(fixture['response'] as Map),
      );
      final authority = MemberSyncSessionAuthority(
        principalId: snapshot.accessContext.principalId,
        organizationId: snapshot.accessContext.organizationId,
        organizationMembershipGeneration:
            snapshot.accessContext.organizationMembershipGeneration,
        offlinePolicy: snapshot.accessContext.offlinePolicy,
        offlinePolicyVersion: snapshot.accessContext.offlinePolicyVersion,
      );
      final material = LocalMemberEntryMaterial(
        item: snapshot.items.single,
        accessContext: snapshot.accessContext,
        memberVaultKey: snapshot.memberVaultKey,
        readGeneration: 7,
      );
      final reader = _MockReader();
      final authorityProvider = _MockAuthorityProvider();
      final vaultKeys = _MockVaultKeys();
      final entryCrypto = _MockEntryCrypto();
      final adapter = _MockCanonicalAdapter();
      final decryptStarted = Completer<void>();
      final decrypted = Completer<Map<String, dynamic>>();
      var invalidated = false;
      final adaptedSecret = <String, dynamic>{
        'content': <String, dynamic>{'password': 'sensitive'},
      };

      when(
        () => authorityProvider.current(),
      ).thenAnswer((_) async => authority);
      when(
        () => reader.readCurrent(
          vaultId: snapshot.accessContext.vaultId,
          entryId: snapshot.items.single.entryId,
          authority: authority,
        ),
      ).thenAnswer((_) async => material);
      when(
        () => vaultKeys.openMemberVaultKey(
          any(),
          any(),
          expectedOrganizationId: any(named: 'expectedOrganizationId'),
          expectedVaultId: any(named: 'expectedVaultId'),
          expectedVaultKeyVersion: any(named: 'expectedVaultKeyVersion'),
          expectedMemberKeyGeneration: any(
            named: 'expectedMemberKeyGeneration',
          ),
        ),
      ).thenAnswer((_) async => Uint8List(32));
      when(
        () => entryCrypto.openMemberSecret(
          entryKey: any(named: 'entryKey'),
          memberSecret: any(named: 'memberSecret'),
          vaultKey: any(named: 'vaultKey'),
        ),
      ).thenAnswer((_) {
        decryptStarted.complete();
        return decrypted.future;
      });
      when(() => adapter.adaptCanonicalSecret(any())).thenReturn(adaptedSecret);
      when(
        () => reader.revalidateCurrent(
          vaultId: snapshot.accessContext.vaultId,
          entryId: snapshot.items.single.entryId,
          material: material,
          authority: authority,
        ),
      ).thenAnswer((_) async {
        if (invalidated) {
          throw const LocalMemberEntryReadInvalidatedException();
        }
      });
      final service = LocalCurrentEntryService(
        reader: reader,
        authorityProvider: authorityProvider,
        vaultKeys: vaultKeys,
        entryCrypto: entryCrypto,
        canonicalAdapter: adapter,
      );

      final reveal = service.revealCurrent(
        vaultId: snapshot.accessContext.vaultId,
        entryId: snapshot.items.single.entryId,
        memberPrivateKey: Uint8List(32),
      );
      await decryptStarted.future;
      invalidated = true;
      decrypted.complete(<String, dynamic>{'authenticated': true});

      await expectLater(
        reveal,
        throwsA(
          isA<CanonicalEntryDetailException>().having(
            (error) => error.kind,
            'kind',
            CanonicalEntryDetailError.conflict,
          ),
        ),
      );
      expect(adaptedSecret, isEmpty);
      verify(
        () => reader.revalidateCurrent(
          vaultId: snapshot.accessContext.vaultId,
          entryId: snapshot.items.single.entryId,
          material: material,
          authority: authority,
        ),
      ).called(1);
    },
  );
}
