import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_palladin/core/di/injection.dart';
import 'package:mobile_palladin/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:mobile_palladin/features/shell/presentation/pages/app_shell.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/vault_list_cubit.dart';
import 'package:mobile_palladin/features/vault/presentation/pages/vault_list_page.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

class _AuthBloc extends Mock implements AuthBloc {}

class _VaultListCubit extends Mock implements VaultListCubit {}

void main() {
  late _AuthBloc authBloc;
  late _VaultListCubit vaultListCubit;

  setUp(() async {
    await getIt.reset();
    authBloc = _AuthBloc();
    vaultListCubit = _VaultListCubit();
    when(() => authBloc.state).thenReturn(const AuthInitial());
    when(() => authBloc.stream).thenAnswer((_) => const Stream.empty());
    when(() => vaultListCubit.state).thenReturn(const VaultListLocked());
    when(() => vaultListCubit.stream).thenAnswer((_) => const Stream.empty());
    when(
      () => vaultListCubit.loadIfNeeded(any<Uint8List?>()),
    ).thenAnswer((_) async {});
    when(() => vaultListCubit.lock()).thenReturn(null);
    getIt.registerSingleton<VaultListCubit>(vaultListCubit);
  });

  tearDown(() => getIt.reset());

  testWidgets('deactivation and teardown never look up AuthBloc in dispose', (
    tester,
  ) async {
    Widget app(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: AppShellScope(
        openSettingsDrawer: () {},
        setBottomNavHidden: (_) {},
        setFab: (_, _) {},
        clearFab: (_) {},
        child: child,
      ),
    );

    await tester.pumpWidget(
      app(
        BlocProvider<AuthBloc>.value(
          value: authBloc,
          child: const VaultListPage(),
        ),
      ),
    );
    await tester.pump();

    // Remove the provider together with its descendant. A context.read from
    // VaultListPage.dispose would now query a deactivated ancestor.
    await tester.pumpWidget(app(const SizedBox.shrink()));
    await tester.pump();

    expect(tester.takeException(), isNull);
    verify(vaultListCubit.lock).called(1);
  });
}
