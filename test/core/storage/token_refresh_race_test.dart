import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/core/storage/secure_token_storage.dart';

class _Storage extends Mock implements FlutterSecureStorage {}

void main() {
  for (final loginAgain in [false, true]) {
    test(
      'held refresh cannot overwrite logout/new login ($loginAgain)',
      () async {
        final storage = _Storage();
        final values = <String, String>{};
        final entered = Completer<void>();
        final release = Completer<void>();
        var hold = false;
        when(
          () => storage.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          ),
        ).thenAnswer((call) async {
          final key = call.namedArguments[#key] as String;
          final value = call.namedArguments[#value] as String;
          if (hold) {
            if (!entered.isCompleted) entered.complete();
            await release.future;
          }
          values[key] = value;
        });
        when(
          () => storage.read(key: any(named: 'key')),
        ).thenAnswer((call) async => values[call.namedArguments[#key]]);
        when(() => storage.deleteAll()).thenAnswer((_) async => values.clear());
        final tokens = SecureTokenStorage(storage);
        await tokens.saveTokens(
          accessToken: 'old',
          refreshToken: 'old-refresh',
          userId: 'old-user',
          isOnboarded: true,
        );
        hold = true;
        final refresh = tokens.updateTokens(
          accessToken: 'late',
          refreshToken: 'late-refresh',
        );
        await entered.future;
        final logout = tokens.clearAll();
        hold = false;
        final login = loginAgain
            ? tokens.saveTokens(
                accessToken: 'new',
                refreshToken: 'new-refresh',
                userId: 'new-user',
                isOnboarded: true,
              )
            : Future<void>.value();
        release.complete();
        await Future.wait([refresh, logout, login]);
        expect(await tokens.accessToken, loginAgain ? 'new' : isNull);
        expect(await tokens.refreshToken, loginAgain ? 'new-refresh' : isNull);
      },
    );
  }
}
