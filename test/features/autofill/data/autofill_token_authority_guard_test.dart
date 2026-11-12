import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/core/storage/secure_token_storage.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_source_access_service.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_token_authority_guard.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_session_authority_provider.dart';

class _Storage extends Mock implements FlutterSecureStorage {}

String _token([Map<String, Object?> changes = const {}]) {
  final claims = <String, Object?>{
    'sub': 'p',
    'org_id': 'o',
    'authz_ver': 1,
    'org_offline_policy': 3,
    'org_offline_policy_ver': 1,
    ...changes,
  };
  return 'e30.${base64Url.encode(utf8.encode(jsonEncode(claims)))}.synthetic';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/token-source-transition');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Map<String, String> stored;
  late SecureTokenStorage tokens;
  late AutoFillSourceAccessService source;
  late List<String> events;
  late int epoch;
  Completer<void>? deny;
  bool failDeny = false;

  setUp(() async {
    stored = {'access_token': _token(), 'refresh_token': 'synthetic'};
    events = [];
    epoch = 0;
    deny = null;
    failDeny = false;
    final native = _Storage();
    when(
      () => native.read(key: any(named: 'key')),
    ).thenAnswer((call) async => stored[call.namedArguments[#key]]);
    when(
      () => native.write(
        key: any(named: 'key'),
        value: any(named: 'value'),
      ),
    ).thenAnswer((call) async {
      events.add('write');
      stored[call.namedArguments[#key] as String] =
          call.namedArguments[#value] as String;
    });
    when(() => native.deleteAll()).thenAnswer((_) async => stored.clear());
    tokens = SecureTokenStorage(
      native,
      beforeAccessTokenWrite: (previous, next) => guardAutoFillTokenReplacement(
        previous: previous,
        next: next,
        source: source,
      ),
    );
    source = AutoFillSourceAccessService(
      channel: channel,
      loadConfiguration: () async {
        final authority = await MemberSyncSessionAuthorityProvider(
          tokens,
        ).captureForPreparation();
        return AutoFillSourceConfiguration(
          authority: authority.claims,
          profileBinding: 'a' * 64,
          accountUnlock: const {},
          validateCurrent: authority.validateCurrent,
        );
      },
    );
    messenger.setMockMethodCallHandler(channel, (call) async {
      events.add(call.method);
      switch (call.method) {
        case 'sourceSnapshot':
          return {'sourceEpoch': epoch, 'profileDigest': 'digest'};
        case 'revokeSourceSession':
        case 'revokeSource':
          await deny?.future;
          if (failDeny) throw PlatformException(code: 'denial_failed');
          return ++epoch;
        case 'beginSourceSession':
          return ++epoch;
        default:
          return null;
      }
    });
    await source.ensureSession();
    events.clear();
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  for (final change in [
    {'org_id': 'other'},
    {'authz_ver': 2},
    {'org_offline_policy': 0},
    {'org_offline_policy_ver': 2},
    {'sub': 'other'},
  ]) {
    test('changed authority $change denies then reboots source', () async {
      final old = await source.ticket();
      await tokens.updateTokens(
        accessToken: _token(change),
        refreshToken: 'new',
      );
      expect(() => source.validateTicket(old), throwsStateError);
      expect(events.indexOf('revokeSourceSession'), greaterThanOrEqualTo(0));
      expect(
        events.indexOf('revokeSourceSession'),
        lessThan(events.indexOf('write')),
      );
      await source.ensureSession();
      source.validateAuthority(
        await source.ticket(),
        await MemberSyncSessionAuthorityProvider(tokens).current(),
      );
      expect(events.where((e) => e == 'beginSourceSession'), hasLength(1));
    });
  }
  test(
    'same-account login replacement also denies changed authority',
    () async {
      final old = await source.ticket();
      await tokens.saveTokens(
        accessToken: _token({'authz_ver': 2}),
        refreshToken: 'new',
        userId: 'p',
        isOnboarded: true,
      );
      expect(() => source.validateTicket(old), throwsStateError);
      expect(
        events.indexOf('revokeSourceSession'),
        lessThan(events.indexOf('write')),
      );
      await source.ensureSession();
      source.validateAuthority(
        await source.ticket(),
        await MemberSyncSessionAuthorityProvider(tokens).current(),
      );
    },
  );

  test('missing authority cannot retain old protected source', () async {
    final old = await source.ticket();
    await tokens.updateTokens(
      accessToken: _token({'org_offline_policy': null}),
      refreshToken: 'new',
    );
    expect(() => source.validateTicket(old), throwsStateError);
    await expectLater(source.ensureSession(), throwsFormatException);
    expect(events, contains('revokeSourceSession'));
  });

  test('same claims with refreshed expiry do not restart source', () async {
    final old = await source.ticket();
    await tokens.updateTokens(
      accessToken: _token({
        'exp': 9999999999,
        'authz_ver': '1',
        'org_offline_policy_ver': '1',
      }),
      refreshToken: 'new',
    );
    source.validateTicket(old);
    expect(events, everyElement('write'));
  });
  test('failed durable denial prevents accepting changed tokens', () async {
    failDeny = true;
    await expectLater(
      tokens.updateTokens(
        accessToken: _token({'authz_ver': 2}),
        refreshToken: 'new',
      ),
      throwsA(isA<PlatformException>()),
    );
    expect(stored['access_token'], _token());
    expect(events, isNot(contains('write')));
  });
  test(
    'held denial hides new authority and logout cancels pending token write',
    () async {
      deny = Completer<void>();
      final refresh = tokens.updateTokens(
        accessToken: _token({'authz_ver': 2}),
        refreshToken: 'new',
      );
      await Future<void>.delayed(Duration.zero);
      expect(stored['access_token'], _token());
      final logout = tokens.clearAll();
      deny!.complete();
      await Future.wait([refresh, logout]);
      expect(events, isNot(contains('write')));
      expect(stored, isEmpty);
    },
  );
}
