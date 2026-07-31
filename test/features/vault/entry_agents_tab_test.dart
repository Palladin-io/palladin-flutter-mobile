import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_palladin/core/di/injection.dart';
import 'package:mobile_palladin/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:mobile_palladin/features/grants/domain/repositories/grants_repository.dart';
import 'package:mobile_palladin/features/grants/presentation/cubit/org_grants_cubit.dart';
import 'package:mobile_palladin/features/vault/data/services/canonical_entry_detail_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_entity.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/entry_agents_cubit.dart';
import 'package:mobile_palladin/features/vault/presentation/pages/entry_agents_tab.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

class _AuthBloc extends Mock implements AuthBloc {}

class _Service extends Mock implements CanonicalEntryDetailService {}

class _Grants extends Mock implements GrantsRepository {}

void main() {
  late _AuthBloc auth;
  late _Service service;
  late _Grants grants;
  late EntryAgentsCubit cubit;
  final entry = EntryEntity(
    id: '33333333-3333-4333-8333-333333333333',
    vaultId: '22222222-2222-4222-8222-222222222222',
    label: 'Member label',
    type: EntryType.credential,
    createdAt: DateTime.utc(2026, 7, 1),
    updatedAt: DateTime.utc(2026, 7, 2),
  );

  setUpAll(() => registerFallbackValue(Uint8List(0)));

  setUp(() async {
    await getIt.reset();
    auth = _AuthBloc();
    service = _Service();
    grants = _Grants();
    cubit = EntryAgentsCubit(service);
    when(() => auth.state).thenReturn(
      AuthAuthenticated(
        userId: 'user',
        isOnboarded: true,
        isVaultLocked: false,
        privateKey: Uint8List.fromList(List<int>.filled(32, 3)),
      ),
    );
    when(() => auth.stream).thenAnswer((_) => const Stream.empty());
    when(
      () => service.reveal(
        expected: entry,
        memberPrivateKey: any(named: 'memberPrivateKey'),
      ),
    ).thenAnswer(
      (_) async => CanonicalEntrySnapshot(
        entry: {
          'organizationId': '11111111-1111-4111-8111-111111111111',
          'vaultId': entry.vaultId,
          'id': entry.id,
        },
        payload: {'username': 'visible-user', 'password': 'TOPSECRET'},
        secret: {
          'memberLabel': 'Member label',
          'agentLabel': 'Agent account',
          'agentVisibilityPolicy': {
            'discoverable': true,
            'fields': {
              'agentLabel': 'discovery',
              'username': 'discovery',
              'password': 'onGrantValue',
            },
          },
        },
      ),
    );
    when(
      () => grants.listOrgGrants(
        agentId: any(named: 'agentId'),
        vaultId: any(named: 'vaultId'),
        entryId: any(named: 'entryId'),
        pageSize: any(named: 'pageSize'),
      ),
    ).thenAnswer((_) async => const GrantListPage(grants: []));
    getIt.registerFactory<OrgGrantsCubit>(
      () => OrgGrantsCubit(repository: grants),
    );
  });

  tearDown(() async {
    await cubit.close();
    await getIt.reset();
  });

  testWidgets('shows grants only and never exposes the policy editor', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MultiBlocProvider(
          providers: [
            BlocProvider<AuthBloc>.value(value: auth),
            BlocProvider<EntryAgentsCubit>.value(value: cubit),
          ],
          child: Scaffold(
            body: EntryAgentsTab(
              entry: entry,
              grantsRefresh: 0,
              onUpdated: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.entryAgentsEmptyTitle), findsOneWidget);
    expect(find.text(l10n.entryAgentsPolicyTitle), findsNothing);
    expect(find.byType(DropdownButton), findsNothing);
    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.textContaining('urlDomain'), findsNothing);
    expect(find.textContaining('totp'), findsNothing);
    expect(find.textContaining('TOPSECRET'), findsNothing);
    for (final forbidden in ['VK', 'VDK', 'EntryDEK', 'TOTP seed']) {
      expect(find.textContaining(forbidden), findsNothing);
    }

    verify(
      () => grants.listOrgGrants(
        entryId: entry.id,
        agentId: null,
        vaultId: null,
        pageSize: any(named: 'pageSize'),
      ),
    ).called(1);
  });
}
