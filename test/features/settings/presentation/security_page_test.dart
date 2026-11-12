import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/auth/domain/auth_provider_id.dart';
import 'package:mobile_palladin/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:mobile_palladin/features/settings/presentation/pages/security_page.dart';
import 'package:mobile_palladin/features/shell/presentation/pages/app_shell.dart';
import 'package:mobile_palladin/features/unlock/data/models/account_response.dart';
import 'package:mobile_palladin/features/unlock/data/services/identity_kdf_service.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';
import 'package:mocktail/mocktail.dart';

class _AuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

IdentityKdfMetadata _kdf(int credentialRevision) => IdentityKdfMetadata(
  securityVersion: 1,
  minimumSecurityVersion: 1,
  profileId: IdentityKdfProfile.id,
  kdfSalt: 'AAECAwQFBgcICQoLDA0ODw',
  credentialRevision: credentialRevision,
  privateKeyWrapRevision: 1,
);

void main() {
  late _AuthBloc auth;

  setUp(() => auth = _AuthBloc());
  tearDown(() => auth.close());

  Future<void> pump(
    WidgetTester tester, {
    required String provider,
    required IdentityKdfMetadata? kdf,
  }) async {
    when(() => auth.state).thenReturn(
      AuthAuthenticated(
        userId: 'account',
        isOnboarded: true,
        authProvider: provider,
      ),
    );
    await tester.pumpWidget(
      BlocProvider<AuthBloc>.value(
        value: auth,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => AppShellScope(
            openSettingsDrawer: () {},
            setBottomNavHidden: (_) {},
            setFab: (_, _) {},
            clearFab: (_) {},
            child: child!,
          ),
          home: SecurityPage(
            loadAccount: () async =>
                AccountResponse(userId: 'account', kdf: kdf),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final provider in [AuthProviderId.password, AuthProviderId.google]) {
    testWidgets('$provider account with a password credential sees TOTP', (
      tester,
    ) async {
      await pump(tester, provider: provider, kdf: _kdf(1));

      expect(find.text('Two-factor authentication'), findsOneWidget);
    });

    for (final (label, kdf) in [
      ('no KDF', null),
      ('credential revision 0', _kdf(0)),
    ]) {
      testWidgets('$provider account with $label hides TOTP', (tester) async {
        await pump(tester, provider: provider, kdf: kdf);

        expect(find.text('Two-factor authentication'), findsNothing);
      });
    }
  }
}
