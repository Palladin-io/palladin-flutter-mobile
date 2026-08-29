import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/core/storage/secure_token_storage.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_session_authority_provider.dart';

class _MockTokenStorage extends Mock implements SecureTokenStorage {}

String _token(Map<String, Object?> payload) {
  final encoded = base64Url
      .encode(utf8.encode(jsonEncode(payload)))
      .replaceAll('=', '');
  return 'header.$encoded.signature';
}

void main() {
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
