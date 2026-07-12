import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/auth/domain/auth_provider_id.dart';
import 'package:mobile_palladin/features/auth/presentation/bloc/auth_state.dart';

void main() {
  group('AuthAuthenticated.isPasswordAccount', () {
    AuthAuthenticated authWith(String? provider) => AuthAuthenticated(
          userId: 'u1',
          isOnboarded: true,
          authProvider: provider,
        );

    test('true only for a password account', () {
      expect(authWith(AuthProviderId.password).isPasswordAccount, isTrue);
    });

    test('false for an OAuth (google) account', () {
      expect(authWith(AuthProviderId.google).isPasswordAccount, isFalse);
    });

    test('false when the provider is unknown (null)', () {
      // A pre-marker / unknown session must read as non-password so a broken
      // change-password / TOTP action is never shown to an OAuth user.
      expect(authWith(null).isPasswordAccount, isFalse);
    });

    test('copyWith preserves authProvider', () {
      final updated =
          authWith(AuthProviderId.password).copyWith(isVaultLocked: false);
      expect(updated.isPasswordAccount, isTrue);
      expect(updated.authProvider, AuthProviderId.password);
    });
  });
}
