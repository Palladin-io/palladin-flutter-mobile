import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_palladin/core/di/injection.dart';
import 'package:mobile_palladin/features/grants/domain/entities/grant.dart';
import 'package:mobile_palladin/features/grants/domain/repositories/grants_repository.dart';
import 'package:mobile_palladin/features/grants/presentation/cubit/org_grants_cubit.dart';
import 'package:mobile_palladin/features/vault/presentation/widgets/vault_agents_tab.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

class _GrantsRepository extends Mock implements GrantsRepository {}

void main() {
  late _GrantsRepository grantsRepository;

  setUp(() async {
    await getIt.reset();
    grantsRepository = _GrantsRepository();
    when(
      () => grantsRepository.listOrgGrants(
        agentId: any(named: 'agentId'),
        vaultId: any(named: 'vaultId'),
        entryId: any(named: 'entryId'),
        pageSize: any(named: 'pageSize'),
      ),
    ).thenAnswer((_) async => const GrantListPage(grants: []));
    getIt.registerFactory<OrgGrantsCubit>(
      () => OrgGrantsCubit(repository: grantsRepository),
    );
  });

  tearDown(() => getIt.reset());

  testWidgets('shows the Vault grant flow without Agent Discovery UI', (
    tester,
  ) async {
    const vaultId = '22222222-2222-4222-8222-222222222222';
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: VaultAgentsTab(vaultId: vaultId)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(l10n.vaultAgentsEmptyTitle), findsOneWidget);
    expect(find.text(l10n.vaultDiscoveryTitle), findsNothing);
    verify(
      () => grantsRepository.listOrgGrants(
        agentId: null,
        vaultId: vaultId,
        entryId: null,
        pageSize: 100,
      ),
    ).called(1);
  });

  testWidgets('reloads scoped grants after returning from pending review', (
    tester,
  ) async {
    const vaultId = '22222222-2222-4222-8222-222222222222';
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    var requests = 0;
    when(
      () => grantsRepository.listOrgGrants(
        agentId: any(named: 'agentId'),
        vaultId: any(named: 'vaultId'),
        entryId: any(named: 'entryId'),
        pageSize: any(named: 'pageSize'),
      ),
    ).thenAnswer((_) async {
      requests += 1;
      return requests == 1
          ? GrantListPage(
              grants: [
                Grant(
                  id: 'pending-grant',
                  vaultId: vaultId,
                  vaultName: 'Production',
                  agentId: 'agent',
                  agentName: 'Deploy Agent',
                  status: GrantStatus.pending,
                  scope: GrantScope.full,
                  createdAt: DateTime(2026, 8, 1),
                ),
              ],
            )
          : const GrantListPage(grants: []);
    });
    final router = GoRouter(
      initialLocation: '/grants',
      routes: [
        GoRoute(
          path: '/grants',
          builder: (_, _) =>
              const Scaffold(body: VaultAgentsTab(vaultId: vaultId)),
        ),
        GoRoute(
          path: '/inbox',
          builder: (context, _) => Scaffold(
            body: TextButton(
              onPressed: () => context.pop(),
              child: const Text('Finish review'),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Review request'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finish review'));
    await tester.pumpAndSettle();

    expect(requests, 2);
    expect(find.text(l10n.vaultAgentsEmptyTitle), findsOneWidget);
  });
}
