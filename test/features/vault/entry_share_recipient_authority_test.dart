import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/core/crypto/vault_session_store.dart';
import 'package:mobile_palladin/core/storage/secure_token_storage.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_sharing/entry_share_recipient_authority.dart';

class _Tokens extends Mock implements SecureTokenStorage {}

String _token(Map<String, Object?> claims) =>
    'header.${base64Url.encode(utf8.encode(jsonEncode(claims)))}.signature';

void main() {
  late _Tokens tokens;
  late VaultSessionStore keys;
  late EntryShareRecipientAuthority authority;
  setUp(() {
    tokens = _Tokens();
    keys = VaultSessionStore();
    authority = EntryShareRecipientAuthority(tokens, keys);
  });
  test(
    'guest is an explicit owner without accessing account token storage',
    () async {
      final owner = await authority.read(null);
      expect(owner, (
        principalId: null,
        organizationId: null,
        authorizationGeneration: null,
        keyGeneration: 0,
      ));
      verifyZeroInteractions(tokens);
    },
  );
  test(
    'authenticated owner binds principal, organization, authz and RAM key generation',
    () async {
      keys.setMemberPrivateKey(Uint8List(32));
      when(() => tokens.accessToken).thenAnswer(
        (_) async =>
            _token({'sub': 'user-a', 'org_id': 'org-a', 'authz_ver': 7}),
      );
      final owner = await authority.read('user-a');
      expect(owner, (
        principalId: 'user-a',
        organizationId: 'org-a',
        authorizationGeneration: '7',
        keyGeneration: 1,
      ));
    },
  );
  test(
    'new account without a vault/org or offline policy can receive independently',
    () async {
      when(
        () => tokens.accessToken,
      ).thenAnswer((_) async => _token({'sub': 'user-a', 'authz_ver': '0'}));
      final owner = await authority.read('user-a');
      expect(owner?.principalId, 'user-a');
      expect(owner?.organizationId, null);
    },
  );
  test(
    'foreign or absent principal and missing authority cannot become a guest',
    () async {
      for (final value in [
        null,
        'invalid',
        _token({'sub': 'user-b', 'authz_ver': '1'}),
        _token({'sub': 'user-a'}),
      ]) {
        when(() => tokens.accessToken).thenAnswer((_) async => value);
        expect(await authority.read('user-a'), isNull);
      }
    },
  );
  test(
    'key generation changed while reading rejects the old authority',
    () async {
      final pending = Completer<String?>();
      when(() => tokens.accessToken).thenAnswer((_) => pending.future);
      final read = authority.read('user-a');
      keys.setMemberPrivateKey(Uint8List(32));
      pending.complete(_token({'sub': 'user-a', 'authz_ver': 1}));
      expect(await read, isNull);
    },
  );
}
