import 'dart:convert';
import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/core/storage/secure_token_storage.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_session_authority_provider.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_service.dart';

class _NativeStorage extends Mock implements FlutterSecureStorage {}

class _MockTokenStorage extends Mock implements SecureTokenStorage {}

String _token(Map<String, Object?> payload) {
  final encoded = base64Url
      .encode(utf8.encode(jsonEncode(payload)))
      .replaceAll('=', '');
  return 'header.$encoded.signature';
}

void main() {
  const protectedClaims = MemberSyncSessionAuthority(
    principalId: 'member',
    organizationId: 'org',
    organizationMembershipGeneration: '7',
    offlinePolicy: '24h',
    offlinePolicyVersion: 2,
  );
  test(
    'protected independent authority is fenced by its native source revision',
    () async {
      var revision = 3;
      var reads = 0;
      final provider = MemberSyncSessionAuthorityProvider.independent(
        readClaims: () async {
          reads++;
          return protectedClaims;
        },
        sessionRevision: () => revision,
      );
      final snapshot = await provider.captureForPreparation();
      expect(snapshot.claims.organizationMembershipGeneration, '7');
      expect(snapshot.claims.offlinePolicyVersion, 2);
      snapshot.requireProvider(provider);
      for (var i = 0; i < 5; i++) {
        snapshot.validateCurrent();
      }
      expect(reads, 1);
      revision++;
      expect(snapshot.validateCurrent, throwsStateError);
      final replacement = await provider.captureForPreparation();
      replacement.validateCurrent();
      expect(
        () => replacement.requireProvider(
          MemberSyncSessionAuthorityProvider.independent(
            readClaims: () async => protectedClaims,
            sessionRevision: () => revision,
          ),
        ),
        throwsStateError,
      );
    },
  );
  test(
    'native source invalidation during protected claims read rejects capture',
    () async {
      var revision = 1;
      final pending = Completer<MemberSyncSessionAuthority>();
      final provider = MemberSyncSessionAuthorityProvider.independent(
        readClaims: () => pending.future,
        sessionRevision: () => revision,
      );
      final capture = provider.captureForPreparation();
      final rejected = expectLater(capture, throwsStateError);
      revision++;
      pending.complete(protectedClaims);
      await rejected;
    },
  );

  test(
    'preparation snapshot reads once and rejects refresh save clear and other owner',
    () async {
      final native = _NativeStorage();
      var reads = 0;
      final token = _token({
        'sub': 'member',
        'org_id': 'org',
        'authz_ver': '1',
        'org_offline_policy': 3,
        'org_offline_policy_ver': 1,
      });
      when(() => native.read(key: any(named: 'key'))).thenAnswer((_) async {
        reads++;
        return token;
      });
      when(
        () => native.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        ),
      ).thenAnswer((_) async {});
      when(() => native.deleteAll()).thenAnswer((_) async {});
      final storage = SecureTokenStorage(native);
      final provider = MemberSyncSessionAuthorityProvider(storage);
      final snapshot = await provider.captureForPreparation();
      for (var index = 0; index < 200; index++) {
        snapshot.validateCurrent();
      }
      expect(reads, 1);
      expect(
        () => snapshot.requireProvider(
          MemberSyncSessionAuthorityProvider(storage),
        ),
        throwsStateError,
      );
      snapshot.requireProvider(provider);
      await storage.updateTokens(accessToken: token, refreshToken: 'synthetic');
      expect(snapshot.validateCurrent, throwsStateError);
      final refreshed = await provider.captureForPreparation();
      final save = storage.saveTokens(
        accessToken: token,
        refreshToken: 'synthetic',
        userId: 'member',
        isOnboarded: true,
      );
      expect(refreshed.validateCurrent, throwsStateError);
      await save;
      final saved = await provider.captureForPreparation();
      final clear = storage.clearAll();
      expect(saved.validateCurrent, throwsStateError);
      await clear;
    },
  );

  test('mutation while token read is pending rejects capture', () async {
    final native = _NativeStorage();
    final read = Completer<String?>();
    when(
      () => native.read(key: any(named: 'key')),
    ).thenAnswer((_) => read.future);
    when(() => native.deleteAll()).thenAnswer((_) async {});
    final storage = SecureTokenStorage(native);
    final provider = MemberSyncSessionAuthorityProvider(storage);
    final capture = provider.captureForPreparation();
    final rejected = expectLater(capture, throwsStateError);
    await Future<void>.delayed(Duration.zero);
    await storage.clearAll();
    read.complete(
      _token({
        'sub': 'member',
        'org_id': 'org',
        'authz_ver': '1',
        'org_offline_policy': 3,
        'org_offline_policy_ver': 1,
      }),
    );
    await rejected;
  });

  test('binds membership and offline policy claims from the token', () async {
    final storage = _MockTokenStorage();
    when(() => storage.accessToken).thenAnswer(
      (_) async => _token({
        'sub': '44444444-4444-4444-8444-444444444444',
        'org_id': '11111111-1111-4111-8111-111111111111',
        'authz_ver': '7',
        'org_offline_policy': 3,
        'org_offline_policy_ver': '2',
      }),
    );

    final authority = await MemberSyncSessionAuthorityProvider(
      storage,
    ).current();

    expect(authority.organizationMembershipGeneration, '7');
    expect(authority.offlinePolicy, '24h');
    expect(authority.offlinePolicyVersion, 2);
  });

  test('fails closed when offline policy claims are absent', () async {
    final storage = _MockTokenStorage();
    when(() => storage.accessToken).thenAnswer(
      (_) async => _token({
        'sub': '44444444-4444-4444-8444-444444444444',
        'org_id': '11111111-1111-4111-8111-111111111111',
        'authz_ver': '7',
      }),
    );

    await expectLater(
      MemberSyncSessionAuthorityProvider(storage).current(),
      throwsFormatException,
    );
  });
}
